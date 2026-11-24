//! PostgreSQL 连接池与就绪探针。

use std::time::Duration;

use application::health::HealthProbe;
use async_trait::async_trait;
use shared::config::DatabaseConfig;
use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;

/// 获取连接的最长等待时间。
pub const ACQUIRE_TIMEOUT: Duration = Duration::from_secs(5);
/// 单次就绪探测的超时。
pub const PROBE_TIMEOUT: Duration = Duration::from_secs(2);

/// 建立连接池失败。
#[derive(Debug, thiserror::Error)]
#[error("PostgreSQL 连接失败")]
pub struct DbError(#[source] sqlx::Error);

/// 按配置建立连接池；启动期立即建立一条连接，失败即返回错误。
pub async fn connect(config: &DatabaseConfig) -> Result<PgPool, DbError> {
    PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(ACQUIRE_TIMEOUT)
        .connect(config.url())
        .await
        .map_err(DbError)
}

/// PostgreSQL 就绪探针：`SELECT 1`，2 秒超时。
pub struct PgProbe {
    pool: PgPool,
}

impl PgProbe {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl HealthProbe for PgProbe {
    fn name(&self) -> &'static str {
        "postgres"
    }

    async fn check(&self) -> Result<(), String> {
        let query = sqlx::query_scalar::<_, i32>("SELECT 1").fetch_one(&self.pool);
        match tokio::time::timeout(PROBE_TIMEOUT, query).await {
            Ok(Ok(1)) => Ok(()),
            Ok(Ok(_)) => Err("postgres: SELECT 1 返回非预期值".to_owned()),
            Ok(Err(error)) => {
                tracing::warn!(error = %error, "postgres 就绪探测失败");
                Err("postgres: 查询失败".to_owned())
            }
            Err(_) => {
                tracing::warn!("postgres 就绪探测超时");
                Err("postgres: 探测超时".to_owned())
            }
        }
    }
}
