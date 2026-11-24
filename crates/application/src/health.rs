//! 就绪检查端口与编排。
//!
//! 依赖可用性由基础设施层实现 [`HealthProbe`]，本模块只负责按顺序执行、
//! 计时并汇总结果，不感知 PostgreSQL / Redis 的具体客户端。

use std::sync::Arc;
use std::time::Instant;

use async_trait::async_trait;

/// 单个依赖的探活端口。实现方必须自带超时，避免阻塞就绪检查。
#[async_trait]
pub trait HealthProbe: Send + Sync {
    /// 稳定的探针名，用于 `/readyz` 输出与日志。
    fn name(&self) -> &'static str;

    /// 执行一次探活；失败时返回**脱敏后**的简短原因（不得含连接串）。
    async fn check(&self) -> Result<(), String>;
}

/// 探针状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeStatus {
    Up,
    Down,
}

impl ProbeStatus {
    /// 稳定的字符串表示，用于 JSON 响应。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Up => "up",
            Self::Down => "down",
        }
    }
}

/// 单个探针的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProbeReport {
    pub name: &'static str,
    pub status: ProbeStatus,
    pub latency_ms: u64,
    pub error: Option<String>,
}

/// 就绪检查集合。
#[derive(Clone, Default)]
pub struct Readiness {
    probes: Vec<Arc<dyn HealthProbe>>,
}

impl Readiness {
    /// 按给定顺序构造；顺序即 `/readyz` 输出顺序。
    pub fn new(probes: Vec<Arc<dyn HealthProbe>>) -> Self {
        Self { probes }
    }

    /// 是否未配置任何探针。空集合不得视为就绪。
    pub fn is_empty(&self) -> bool {
        self.probes.is_empty()
    }

    /// 依次执行全部探针并汇总；单个探针失败不影响其余探针执行。
    pub async fn check(&self) -> Vec<ProbeReport> {
        let mut reports = Vec::with_capacity(self.probes.len());
        for probe in &self.probes {
            let started = Instant::now();
            let result = probe.check().await;
            let latency_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
            let (status, error) = match result {
                Ok(()) => (ProbeStatus::Up, None),
                Err(reason) => (ProbeStatus::Down, Some(reason)),
            };
            reports.push(ProbeReport {
                name: probe.name(),
                status,
                latency_ms,
                error,
            });
        }
        reports
    }
}

/// 全部探针均为 `up` 且至少一个探针时才算就绪。
pub fn all_up(reports: &[ProbeReport]) -> bool {
    !reports.is_empty()
        && reports
            .iter()
            .all(|report| report.status == ProbeStatus::Up)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FixedProbe {
        name: &'static str,
        result: Result<(), &'static str>,
    }

    #[async_trait]
    impl HealthProbe for FixedProbe {
        fn name(&self) -> &'static str {
            self.name
        }

        async fn check(&self) -> Result<(), String> {
            self.result.map_err(str::to_owned)
        }
    }

    fn probe(name: &'static str, ok: bool) -> Arc<dyn HealthProbe> {
        Arc::new(FixedProbe {
            name,
            result: if ok { Ok(()) } else { Err("不可用") },
        })
    }

    #[tokio::test]
    async fn reports_every_probe_in_order() {
        let readiness = Readiness::new(vec![probe("postgres", true), probe("redis", true)]);
        let reports = readiness.check().await;

        assert_eq!(reports.len(), 2);
        assert_eq!(reports[0].name, "postgres");
        assert_eq!(reports[1].name, "redis");
        assert!(reports.iter().all(|r| r.status == ProbeStatus::Up));
        assert!(reports.iter().all(|r| r.error.is_none()));
        assert!(all_up(&reports));
    }

    #[tokio::test]
    async fn failure_is_captured_and_others_still_run() {
        let readiness = Readiness::new(vec![probe("postgres", true), probe("redis", false)]);
        let reports = readiness.check().await;

        assert_eq!(reports[0].status, ProbeStatus::Up);
        assert_eq!(reports[1].status, ProbeStatus::Down);
        assert_eq!(reports[1].error.as_deref(), Some("不可用"));
        assert!(!all_up(&reports));
    }

    #[tokio::test]
    async fn empty_readiness_is_not_ready() {
        let reports = Readiness::new(Vec::new()).check().await;

        assert!(reports.is_empty());
        assert!(!all_up(&reports));
    }
}
