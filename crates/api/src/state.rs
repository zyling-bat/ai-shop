//! 进程级共享状态：指标句柄、就绪检查与审计端口。

use std::sync::Arc;

use application::audit::AuditSink;
use application::health::Readiness;
use metrics_exporter_prometheus::PrometheusHandle;

/// 路由与中间件共享的状态。克隆成本为三个引用计数。
#[derive(Clone)]
pub struct AppState {
    /// Prometheus 渲染句柄。
    pub metrics: PrometheusHandle,
    /// 就绪探针集合。
    pub readiness: Arc<Readiness>,
    /// 审计写入端口。
    pub audit: Arc<dyn AuditSink>,
}

impl AppState {
    pub fn new(
        metrics: PrometheusHandle,
        readiness: Arc<Readiness>,
        audit: Arc<dyn AuditSink>,
    ) -> Self {
        Self {
            metrics,
            readiness,
            audit,
        }
    }
}
