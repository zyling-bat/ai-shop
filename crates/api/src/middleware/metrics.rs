//! 指标：Prometheus 记录器安装、请求采集中间件与 `/metrics` 渲染。
//!
//! 指标约定（ADR-008）：
//! - `http_requests_total{method,path,status}`：请求计数（counter，名称按 Prometheus 约定自带 `_total`）
//! - `http_request_duration_seconds{method,path}`：请求耗时（histogram）
//! - `path` 取路由模板，禁止原始 URI，避免标签基数爆炸
//! - `/metrics` 自身的抓取不计入指标，避免抓取频率污染业务口径

use std::time::Instant;

use axum::extract::{MatchedPath, Request, State};
use axum::http::header;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use metrics_exporter_prometheus::{BuildError, PrometheusBuilder, PrometheusHandle};

use crate::state::AppState;

/// 直方图分桶（秒），覆盖本地毫秒级到慢接口的 10s。
const HISTOGRAM_BUCKETS: &[f64] = &[
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

/// 指标抓取路径；该路径的请求不计入指标。
const SCRAPE_PATH: &str = "/metrics";

/// 安装进程级 Prometheus 记录器并返回渲染句柄。
///
/// 进程内只允许安装一次；重复安装返回错误，由启动入口按启动期异常处理。
pub fn install() -> Result<PrometheusHandle, BuildError> {
    let handle = PrometheusBuilder::new()
        .set_buckets(HISTOGRAM_BUCKETS)?
        .install_recorder()?;

    metrics::describe_counter!(
        "http_requests_total",
        "Total number of HTTP requests handled, by method, matched path and status."
    );
    metrics::describe_histogram!(
        "http_request_duration_seconds",
        "HTTP request latency in seconds, by method and matched path."
    );
    metrics::describe_counter!(
        "audit_write_failures_total",
        "Total number of failed audit writes; request responses are unaffected."
    );

    Ok(handle)
}

/// 采集中间件：按路由模板记录计数与耗时。
pub async fn layer(req: Request, next: Next) -> Response {
    if req.uri().path() == SCRAPE_PATH {
        return next.run(req).await;
    }

    let method = req.method().as_str().to_owned();
    let path = req
        .extensions()
        .get::<MatchedPath>()
        .map(|matched| matched.as_str().to_owned())
        .unwrap_or_else(|| "unmatched".to_owned());

    let started = Instant::now();
    let response = next.run(req).await;
    let status = response.status().as_u16().to_string();

    metrics::counter!(
        "http_requests_total",
        "method" => method.clone(),
        "path" => path.clone(),
        "status" => status,
    )
    .increment(1);
    metrics::histogram!(
        "http_request_duration_seconds",
        "method" => method,
        "path" => path,
    )
    .record(started.elapsed().as_secs_f64());

    response
}

/// `/metrics` 处理器：输出 Prometheus 文本格式。
pub async fn scrape(State(state): State<AppState>) -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.metrics.render(),
    )
}
