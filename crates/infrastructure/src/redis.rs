//! Redis 连接池与就绪探针（deadpool-redis，见 ADR-003）。

use std::time::Duration;

use application::health::HealthProbe;
use async_trait::async_trait;
use deadpool_redis::{Config, Pool, Runtime};
use shared::config::RedisConfig;

/// 单次就绪探测的超时。
pub const PROBE_TIMEOUT: Duration = Duration::from_secs(2);

/// 创建连接池失败。
#[derive(Debug, thiserror::Error)]
#[error("Redis 连接池创建失败")]
pub struct RedisError(#[source] Box<dyn std::error::Error + Send + Sync>);

/// 按配置创建连接池；连接在首次使用时建立。
pub fn connect(config: &RedisConfig) -> Result<Pool, RedisError> {
    Config::from_url(config.url())
        .create_pool(Some(Runtime::Tokio1))
        .map_err(|error| RedisError(Box::new(error)))
}

/// Redis 就绪探针：`PING`，2 秒超时。
pub struct RedisProbe {
    pool: Pool,
}

impl RedisProbe {
    pub fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl HealthProbe for RedisProbe {
    fn name(&self) -> &'static str {
        "redis"
    }

    async fn check(&self) -> Result<(), String> {
        let ping = async {
            let mut conn = self.pool.get().await.map_err(|error| error.to_string())?;
            deadpool_redis::redis::cmd("PING")
                .query_async::<String>(&mut conn)
                .await
                .map_err(|error| error.to_string())
        };

        match tokio::time::timeout(PROBE_TIMEOUT, ping).await {
            Ok(Ok(pong)) if pong == "PONG" => Ok(()),
            Ok(Ok(pong)) => {
                tracing::warn!(pong = %pong, "redis 就绪探测返回非预期结果");
                Err("redis: PING 返回非预期结果".to_owned())
            }
            Ok(Err(error)) => {
                tracing::warn!(error = %error, "redis 就绪探测失败");
                Err("redis: PING 失败".to_owned())
            }
            Err(_) => {
                tracing::warn!("redis 就绪探测超时");
                Err("redis: 探测超时".to_owned())
            }
        }
    }
}
