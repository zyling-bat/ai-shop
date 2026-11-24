//! 遥测装配：OTel TracerProvider + `tracing` 订阅器（fmt + OTel 桥接层）。
//!
//! `OTEL_EXPORTER_OTLP_ENDPOINT` 非空时挂 OTLP(gRPC) 批量导出器；为空时只构造
//! 本地 TracerProvider——trace id 仍由 SDK 生成，只是不导出到后端（ADR-008 §5）。

use opentelemetry::trace::TracerProvider as _;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::runtime;
use opentelemetry_sdk::trace::TracerProvider;
use shared::config::{LogConfig, LogFormat, TelemetryConfig};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, fmt};

/// 导出器装配失败。
pub type BuildError = Box<dyn std::error::Error + Send + Sync>;

/// 已安装的遥测资源；进程退出前调用 [`Telemetry::shutdown`] 冲刷导出队列。
pub struct Telemetry {
    provider: TracerProvider,
}

impl Telemetry {
    /// 关闭 TracerProvider 并冲刷未发送的 span。
    pub fn shutdown(&self) {
        if let Err(error) = self.provider.shutdown() {
            tracing::warn!(%error, "OTel provider 关闭失败");
        }
    }
}

/// 按配置构造 TracerProvider；端点非空时安装 OTLP 导出器。
pub fn build_provider(config: &TelemetryConfig) -> Result<TracerProvider, BuildError> {
    let provider = match &config.otlp_endpoint {
        Some(endpoint) => {
            let exporter = opentelemetry_otlp::SpanExporter::builder()
                .with_tonic()
                .with_endpoint(endpoint.clone())
                .build()?;
            TracerProvider::builder()
                .with_batch_exporter(exporter, runtime::Tokio)
                .build()
        }
        None => TracerProvider::builder().build(),
    };
    Ok(provider)
}

/// 安装全局订阅器：`RUST_LOG` 过滤 + fmt 输出 + OTel 桥接层。
pub fn install(log: &LogConfig, service_name: &str, provider: TracerProvider) -> Telemetry {
    opentelemetry::global::set_tracer_provider(provider.clone());
    let tracer = provider.tracer(service_name.to_owned());

    let filter = EnvFilter::try_new(&log.filter).unwrap_or_else(|_| EnvFilter::new("info"));
    let registry = tracing_subscriber::registry()
        .with(filter)
        .with(tracing_opentelemetry::layer().with_tracer(tracer));

    match log.format {
        LogFormat::Json => registry.with(fmt::layer().json()).init(),
        LogFormat::Pretty => registry.with(fmt::layer()).init(),
    }

    Telemetry { provider }
}
