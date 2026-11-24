//! 服务入口：装载配置、装配日志与指标，启动 axum 服务并处理优雅退出。

use std::collections::BTreeMap;
use std::process::ExitCode;

use shared::config::{AppConfig, LogConfig, LogFormat};
use tracing_subscriber::EnvFilter;

/// 启动期配置校验失败的退出码。
const EXIT_CONFIG_INVALID: u8 = 2;
/// 依赖（PostgreSQL / Redis）不可用的退出码。
const EXIT_DEPENDENCY_UNAVAILABLE: u8 = 3;

#[tokio::main]
async fn main() -> ExitCode {
    let vars: BTreeMap<String, String> = std::env::vars().collect();

    // 先按日志相关配置装配输出，保证后续配置问题能被看见。
    init_tracing(&LogConfig::from_map(&vars));

    let config = match AppConfig::from_map(&vars) {
        Ok(config) => config,
        Err(error) => {
            tracing::error!(%error, "配置校验失败，进程退出");
            for issue in &error.issues {
                tracing::error!(key = issue.key(), "{}", issue);
            }
            return ExitCode::from(EXIT_CONFIG_INVALID);
        }
    };

    let metrics = api::middleware::metrics::install()
        // INVARIANT: 进程内首次安装记录器，失败属于启动环境异常，必须终止。
        .expect("安装 Prometheus 记录器失败");

    let bootstrap =
        match infrastructure::bootstrap::bootstrap(&config.database, &config.redis).await {
            Ok(bootstrap) => bootstrap,
            Err(error) => {
                tracing::error!(%error, "依赖装配失败，进程退出");
                return ExitCode::from(EXIT_DEPENDENCY_UNAVAILABLE);
            }
        };

    let state = api::AppState::new(
        metrics,
        bootstrap.readiness.clone(),
        bootstrap.audit.clone(),
    );

    let listener = tokio::net::TcpListener::bind(config.bind_addr)
        .await
        // INVARIANT: 启动期绑定失败即无法提供服务，直接终止而不是静默降级。
        .expect("绑定监听地址失败");

    tracing::info!(
        addr = %config.bind_addr,
        env = config.app_env.as_str(),
        log_format = config.log.format.as_str(),
        database_max_connections = config.database.max_connections,
        "server listening"
    );

    axum::serve(listener, api::router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await
        // INVARIANT: 服务运行期错误视为不可恢复，交由编排层重启。
        .expect("axum 服务异常退出");

    bootstrap.pool.close().await;
    tracing::info!("server stopped");
    ExitCode::SUCCESS
}

/// 装配日志输出：`RUST_LOG` 过滤 + `pretty` / `json` 二选一。
fn init_tracing(log: &LogConfig) {
    let filter = EnvFilter::try_new(&log.filter).unwrap_or_else(|_| EnvFilter::new("info"));
    let builder = tracing_subscriber::fmt().with_env_filter(filter);
    match log.format {
        LogFormat::Json => builder.json().init(),
        LogFormat::Pretty => builder.init(),
    }
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};

        // INVARIANT: SIGTERM 监听器只在启动期注册一次，注册失败属于进程环境异常。
        let mut terminate = signal(SignalKind::terminate()).expect("注册 SIGTERM 处理失败");

        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = terminate.recv() => {}
        }
    }

    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c()
            .await
            // INVARIANT: 无法注册 Ctrl+C 处理时进程只能被强杀，属于进程环境异常。
            .expect("注册 Ctrl+C 处理失败");
    }

    tracing::info!("shutdown signal received");
}
