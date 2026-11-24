//! 审计写入端口。
//!
//! P0 只要求"一次请求能把 `trace_id` 落到 DB"（05 §5.1 P0-5）；业务审计字段
//! 随身份与交易域在后续 ST 扩展。API 层只依赖本端口，不感知表结构。

use async_trait::async_trait;
use thiserror::Error;

/// 一行请求审计。字段均为已脱敏的请求元数据，不含请求体与凭证。
#[derive(Debug, Clone, Copy)]
pub struct AuditEntry<'a> {
    pub trace_id: &'a str,
    pub request_id: &'a str,
    pub method: &'a str,
    pub path: &'a str,
    pub status: u16,
    pub latency_ms: u64,
}

/// 审计写入错误。对 HTTP 调用方保持不透明。
#[derive(Debug, Error)]
#[error("审计写入失败")]
pub struct AuditError(#[source] Box<dyn std::error::Error + Send + Sync>);

impl AuditError {
    /// 包装底层存储错误；调用方不得把 `source` 回显给客户端。
    pub fn unavailable(source: impl std::error::Error + Send + Sync + 'static) -> Self {
        Self(Box::new(source))
    }
}

/// 审计存储端口。
#[async_trait]
pub trait AuditSink: Send + Sync {
    /// 写入一行审计；失败由调用方降级处理（不影响原响应）。
    async fn record(&self, entry: AuditEntry<'_>) -> Result<(), AuditError>;
}
