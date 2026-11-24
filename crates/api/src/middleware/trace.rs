//! 请求日志中间件：为每个请求建立 `http_request` span，并在结束时打一条结构化事件。
//!
//! 事件字段：`method` / `path` / `request_id` / `trace_id` / `status` / `latency_ms`。
//! 本轮 `trace_id` 与 `request_id` 同源（OTel SDK 接入后由 SDK 生成，见 ADR-008）。

use std::time::Instant;

use axum::extract::{MatchedPath, Request};
use axum::middleware::Next;
use axum::response::Response;
use tracing::Instrument;

use super::request_id::RequestId;

/// 中间件本体。必须位于 `request_id` 之后，才能读到请求扩展里的标识。
pub async fn layer(req: Request, next: Next) -> Response {
    let request_id = req
        .extensions()
        .get::<RequestId>()
        .map(|id| id.as_str().to_owned())
        .unwrap_or_default();

    // 优先使用路由模板（低基数）；未命中路由时退回原始路径，仅用于日志定位。
    let path = req
        .extensions()
        .get::<MatchedPath>()
        .map(|matched| matched.as_str().to_owned())
        .unwrap_or_else(|| req.uri().path().to_owned());

    let span = tracing::info_span!(
        "http_request",
        method = %req.method(),
        path = %path,
        request_id = %request_id,
        trace_id = %request_id,
        status = tracing::field::Empty,
        latency_ms = tracing::field::Empty,
    );

    let started = Instant::now();
    let response = next.run(req).instrument(span.clone()).await;
    let status = response.status().as_u16();
    let latency_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);

    span.record("status", status);
    span.record("latency_ms", latency_ms);

    tracing::info!(
        parent: &span,
        status,
        latency_ms,
        "request completed"
    );

    response
}
