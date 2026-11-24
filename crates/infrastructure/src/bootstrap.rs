//! 启动期依赖装配：一次建立连接池、就绪探针与审计端口。

use std::sync::Arc;

use application::audit::AuditSink;
use application::health::{HealthProbe, Readiness};
use shared::config::{DatabaseConfig, RedisConfig};
use sqlx::PgPool;

use crate::audit::PgAuditSink;
use crate::db::PgProbe;
use crate::redis::RedisProbe;

/// 装配结果。`pool` 由调用方负责在退出时关闭。
pub struct Bootstrap {
    pub pool: PgPool,
    pub readiness: Arc<Readiness>,
    pub audit: Arc<dyn AuditSink>,
}

/// 建立全部基础设施依赖；任一失败即返回错误，由入口 fail-fast。
pub async fn bootstrap(
    database: &DatabaseConfig,
    redis: &RedisConfig,
) -> Result<Bootstrap, BootstrapError> {
    let pool = crate::db::connect(database).await?;
    let redis_pool = crate::redis::connect(redis)?;

    let probes: Vec<Arc<dyn HealthProbe>> = vec![
        Arc::new(PgProbe::new(pool.clone())),
        Arc::new(RedisProbe::new(redis_pool)),
    ];

    Ok(Bootstrap {
        pool: pool.clone(),
        readiness: Arc::new(Readiness::new(probes)),
        audit: Arc::new(PgAuditSink::new(pool)),
    })
}

/// 依赖装配失败。
#[derive(Debug, thiserror::Error)]
pub enum BootstrapError {
    #[error(transparent)]
    Postgres(#[from] crate::db::DbError),
    #[error(transparent)]
    Redis(#[from] crate::redis::RedisError),
}
