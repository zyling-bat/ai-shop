//! 服务入口：装配最小 axum 服务（仅 `/healthz`）并处理优雅退出。

use std::net::SocketAddr;

use tracing_subscriber::EnvFilter;

const BIND_ADDR: &str = "0.0.0.0:8080";

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let addr: SocketAddr = BIND_ADDR
        .parse()
        // INVARIANT: BIND_ADDR 是编译期常量，解析失败只可能是该常量被改坏。
        .expect("BIND_ADDR 必须是合法的 socket 地址");

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        // INVARIANT: 启动期绑定失败即无法提供服务，直接终止而不是静默降级。
        .expect("绑定 0.0.0.0:8080 失败");

    tracing::info!(%addr, "server listening");

    axum::serve(listener, api::router())
        .with_graceful_shutdown(shutdown_signal())
        .await
        // INVARIANT: 服务运行期错误视为不可恢复，交由编排层重启。
        .expect("axum 服务异常退出");

    tracing::info!("server stopped");
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
