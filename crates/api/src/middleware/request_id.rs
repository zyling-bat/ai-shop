//! 请求标识中间件：沿用合法入站 `X-Request-Id`，否则生成 UUID v7。
//!
//! 标识会写入请求扩展（供后续中间件与 handler 使用）、响应头与日志 span。

use axum::extract::Request;
use axum::http::HeaderValue;
use axum::middleware::Next;
use axum::response::Response;
use uuid::Uuid;

/// 请求标识头（小写，`http` crate 的头部名规范化形式）。
pub const REQUEST_ID_HEADER: &str = "x-request-id";

/// 入站标识允许的最大字节数，防止超长值污染日志与响应头。
const MAX_LEN: usize = 64;

/// 请求标识（UUID v7 或调用方传入的合法值）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestId(String);

impl RequestId {
    /// 生成时间有序的 UUID v7 作为标识。
    pub fn generate() -> Self {
        Self(Uuid::now_v7().to_string())
    }

    /// 以既有值构造；调用方需保证已通过 [`RequestId::is_valid`] 校验。
    pub fn from_trusted(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// 标识文本。
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// 白名单校验：`[A-Za-z0-9._-]`，长度 1..=64。
    ///
    /// 拒绝控制字符与空格，避免日志注入（C30 的输入白名单化）。
    pub fn is_valid(value: &str) -> bool {
        !value.is_empty()
            && value.len() <= MAX_LEN
            && value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    }
}

impl Default for RequestId {
    fn default() -> Self {
        Self::generate()
    }
}

/// 中间件本体：写入请求扩展并回写响应头。
pub async fn layer(mut req: Request, next: Next) -> Response {
    let incoming = req
        .headers()
        .get(REQUEST_ID_HEADER)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| RequestId::is_valid(value))
        .map(RequestId::from_trusted);

    let request_id = incoming.unwrap_or_default();
    req.extensions_mut().insert(request_id.clone());

    let mut response = next.run(req).await;
    // 标识已通过白名单校验（仅 ASCII 可见字符），构造头部不会失败。
    if let Ok(value) = HeaderValue::from_str(request_id.as_str()) {
        response.headers_mut().insert(REQUEST_ID_HEADER, value);
    }
    response
}

#[cfg(test)]
mod tests {
    use axum::Router;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::middleware::from_fn;
    use axum::routing::get;
    use tower::ServiceExt;
    use uuid::Uuid;

    use super::{REQUEST_ID_HEADER, RequestId, layer};

    fn app() -> Router {
        Router::new()
            .route("/ping", get(|| async { "pong" }))
            .layer(from_fn(layer))
    }

    fn request(request_id: Option<&str>) -> Request<Body> {
        let builder = Request::builder().uri("/ping");
        let builder = match request_id {
            Some(value) => builder.header(REQUEST_ID_HEADER, value),
            None => builder,
        };
        // INVARIANT: 测试用静态 URI 与头部均为合法字面量。
        builder.body(Body::empty()).expect("测试请求构造失败")
    }

    fn sent_id(response: &axum::response::Response) -> String {
        response
            .headers()
            .get(REQUEST_ID_HEADER)
            .and_then(|value| value.to_str().ok())
            .expect("响应必须带 X-Request-Id")
            .to_owned()
    }

    #[tokio::test]
    async fn keeps_valid_incoming_id() {
        let response = app()
            .oneshot(request(Some("p0-trace-001")))
            .await
            .expect("路由调用失败");

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(sent_id(&response), "p0-trace-001");
    }

    #[tokio::test]
    async fn generates_uuid_v7_when_absent() {
        let response = app().oneshot(request(None)).await.expect("路由调用失败");

        let id = sent_id(&response);
        let parsed = Uuid::parse_str(&id).expect("自动生成的标识必须是 UUID");
        assert_eq!(parsed.get_version_num(), 7);
    }

    #[tokio::test]
    async fn replaces_invalid_incoming_id() {
        let invalid = "bad id!with spaces";
        let response = app()
            .oneshot(request(Some(invalid)))
            .await
            .expect("路由调用失败");

        let id = sent_id(&response);
        assert_ne!(id, invalid);
        assert!(Uuid::parse_str(&id).is_ok());
    }

    #[tokio::test]
    async fn rejects_overlong_id() {
        let overlong = "a".repeat(65);
        let response = app()
            .oneshot(request(Some(&overlong)))
            .await
            .expect("路由调用失败");

        let id = sent_id(&response);
        assert_ne!(id, overlong);
        assert_eq!(id.len(), 36, "超长标识应被替换为 UUID");
    }

    #[test]
    fn whitelist_rules() {
        assert!(RequestId::is_valid("abc-123_X.Y"));
        assert!(!RequestId::is_valid(""));
        assert!(!RequestId::is_valid("a b"));
        assert!(!RequestId::is_valid("bad\nvalue"));
        assert!(!RequestId::is_valid(&"a".repeat(65)));
    }
}
