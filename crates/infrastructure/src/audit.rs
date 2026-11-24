//! 审计落库适配器：把 [`AuditEntry`] 写入 `audit_log`。

use application::audit::{AuditEntry, AuditError, AuditSink};
use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;

/// PostgreSQL 审计写入实现。
pub struct PgAuditSink {
    pool: PgPool,
}

impl PgAuditSink {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl AuditSink for PgAuditSink {
    async fn record(&self, entry: AuditEntry<'_>) -> Result<(), AuditError> {
        let status = i16::try_from(entry.status).unwrap_or(0);
        let latency_ms = i32::try_from(entry.latency_ms).unwrap_or(i32::MAX);
        sqlx::query(
            "INSERT INTO audit_log (id, trace_id, request_id, method, path, status, latency_ms) \
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(Uuid::now_v7())
        .bind(entry.trace_id)
        .bind(entry.request_id)
        .bind(entry.method)
        .bind(entry.path)
        .bind(status)
        .bind(latency_ms)
        .execute(&self.pool)
        .await
        .map_err(AuditError::unavailable)?;
        Ok(())
    }
}
