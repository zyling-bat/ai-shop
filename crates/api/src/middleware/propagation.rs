//! W3C `traceparent` 解析与 trace 标识。
//!
//! 只采信严格合法的 `00-<32hex>-<16hex>-<2hex>`（长度 55、全小写十六进制、
//! trace/span 非全零）；其余一律视为缺失，由 OTel SDK 新建 trace。

use opentelemetry::Context;
use opentelemetry::trace::{
    SpanContext, SpanId, TraceContextExt, TraceFlags, TraceId as OtelTraceId, TraceState,
};

/// 入站链路头。
pub const TRACEPARENT_HEADER: &str = "traceparent";
/// 回写给调用方的 trace 标识头（只回 trace id，不回完整 `traceparent`）。
pub const TRACE_ID_HEADER: &str = "x-trace-id";

/// W3C `traceparent` 的固定长度（`00-` + 32 + `-` + 16 + `-` + 2）。
const TRACEPARENT_LEN: usize = 55;

/// 32 位小写十六进制的 trace 标识。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceId(String);

impl TraceId {
    /// 由 OTel trace id 转换（固定 32 位小写十六进制）。
    pub fn from_otel(id: OtelTraceId) -> Self {
        Self(format!("{id:032x}"))
    }

    /// 未装配 OTel 订阅器时的兜底：UUID v7 的 32 位十六进制形式。
    pub fn generate() -> Self {
        Self(uuid::Uuid::now_v7().simple().to_string())
    }

    /// 标识文本。
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// 从入站 `traceparent` 构造父上下文；缺失或非法返回 `None`。
pub fn parent_context(raw: Option<&str>) -> Option<Context> {
    let span_context = parse(raw?)?;
    Some(Context::new().with_remote_span_context(span_context))
}

/// 严格解析 `traceparent`。
pub fn parse(raw: &str) -> Option<SpanContext> {
    let raw = raw.trim();
    if raw.len() != TRACEPARENT_LEN {
        return None;
    }

    let mut parts = raw.split('-');
    let version = parts.next()?;
    let trace = parts.next()?;
    let span = parts.next()?;
    let flags = parts.next()?;
    if parts.next().is_some() {
        return None;
    }

    if version != "00" {
        return None;
    }
    if !is_lower_hex(trace, 32) || trace.bytes().all(|byte| byte == b'0') {
        return None;
    }
    if !is_lower_hex(span, 16) || span.bytes().all(|byte| byte == b'0') {
        return None;
    }
    if !is_lower_hex(flags, 2) {
        return None;
    }

    Some(SpanContext::new(
        OtelTraceId::from_hex(trace).ok()?,
        SpanId::from_hex(span).ok()?,
        TraceFlags::new(u8::from_str_radix(flags, 16).ok()?),
        true,
        TraceState::NONE,
    ))
}

fn is_lower_hex(value: &str, len: usize) -> bool {
    value.len() == len
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID: &str = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    #[test]
    fn accepts_valid_traceparent() {
        let context = parse(VALID).expect("合法报文应解析成功");

        assert_eq!(
            context.trace_id().to_string(),
            "4bf92f3577b34da6a3ce929d0e0e4736"
        );
        assert_eq!(context.span_id().to_string(), "00f067aa0ba902b7");
        assert!(context.is_remote());
        assert!(context.is_sampled());
    }

    #[test]
    fn rejects_malformed_values() {
        for raw in [
            "",
            "00-bad",
            "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
            "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
            "00-4bf92f3577b34da6a3ce929d0e0e473z-00f067aa0ba902b7-01",
            "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-0g",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra",
        ] {
            assert!(parse(raw).is_none(), "非法报文不应被采信：{raw}");
        }
    }

    #[test]
    fn parent_context_requires_valid_header() {
        assert!(parent_context(None).is_none());
        assert!(parent_context(Some("00-bad")).is_none());
        assert!(parent_context(Some(VALID)).is_some());
    }

    #[test]
    fn generated_trace_id_is_32_hex() {
        let id = TraceId::generate();
        assert_eq!(id.as_str().len(), 32);
        assert!(is_lower_hex(id.as_str(), 32));
    }
}
