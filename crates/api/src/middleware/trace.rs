//! 请求日志中间件：为每个请求建立 `http_request` span，并在结束时打一条结构化事件。
//!
//! 事件字段：`method` / `path` / `request_id` / `trace_id` / `status` / `latency_ms`。
//! `trace_id` 取 OTel span context（32 位十六进制），入站 `traceparent` 合法时续接，
//! 否则由 SDK 新建；`request_id` 保持独立语义（见 ADR-008）。

use std::time::Instant;

use axum::extract::{MatchedPath, Request};
use axum::http::HeaderValue;
use axum::middleware::Next;
use axum::response::Response;
use opentelemetry::trace::TraceContextExt;
use tracing::Instrument;
use tracing_opentelemetry::OpenTelemetrySpanExt;

use super::propagation::{self, TraceId};
use super::request_id::RequestId;

/// 中间件本体。必须位于 `request_id` 之后，才能读到请求扩展里的标识。
pub async fn layer(mut req: Request, next: Next) -> Response {
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
        trace_id = tracing::field::Empty,
        status = tracing::field::Empty,
        latency_ms = tracing::field::Empty,
    );

    let incoming = req
        .headers()
        .get(propagation::TRACEPARENT_HEADER)
        .and_then(|value| value.to_str().ok());
    if let Some(parent) = propagation::parent_context(incoming) {
        span.set_parent(parent);
    }

    let trace_id = resolve_trace_id(&span);
    span.record("trace_id", tracing::field::display(trace_id.as_str()));
    req.extensions_mut().insert(trace_id.clone());

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

    let mut response = response;
    // trace id 固定为 ASCII 十六进制，构造头部不会失败。
    if let Ok(value) = HeaderValue::from_str(trace_id.as_str()) {
        response
            .headers_mut()
            .insert(propagation::TRACE_ID_HEADER, value);
    }
    response
}

/// 取当前 span 的 OTel trace id；未装配 OTel 订阅器时兜底生成一个合法十六进制值。
fn resolve_trace_id(span: &tracing::Span) -> TraceId {
    let context = span.context();
    let span_ref = context.span();
    let span_context = span_ref.span_context();
    if span_context.is_valid() {
        TraceId::from_otel(span_context.trace_id())
    } else {
        TraceId::generate()
    }
}
