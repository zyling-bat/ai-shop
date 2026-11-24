//! 请求护栏：CORS → BodyLimit → Timeout（06 §6.3.6）。
//!
//! 三层都排在 `Metrics` 之后、`Audit` 之前，保证被拒绝的请求仍被计数与审计。
//! `BodyLimit` 额外做 Content-Length 预检，确保不读请求体的处理路径也会立即拒绝。

use std::time::Duration;

use axum::Router;
use axum::extract::Request;
use axum::http::{HeaderName, HeaderValue, Method, StatusCode, header};
use axum::middleware::{Next, from_fn};
use axum::response::{IntoResponse, Response};
use shared::config::HttpConfig;
use tower::ServiceBuilder;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;

/// 按固定顺序为路由叠加三层护栏。
pub fn apply_guards<S>(router: Router<S>, config: &HttpConfig) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    let limit = config.body_limit_bytes as usize;
    router.layer(
        ServiceBuilder::new()
            .layer(cors_layer(config))
            .layer(from_fn(move |req, next| reject_oversized(req, next, limit)))
            .layer(RequestBodyLimitLayer::new(limit))
            .layer(TimeoutLayer::with_status_code(
                StatusCode::REQUEST_TIMEOUT,
                Duration::from_secs(config.timeout_secs),
            )),
    )
}

fn cors_layer(config: &HttpConfig) -> CorsLayer {
    let mut layer = CorsLayer::new()
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::PATCH,
            Method::DELETE,
        ])
        .allow_headers([
            header::CONTENT_TYPE,
            header::AUTHORIZATION,
            HeaderName::from_static("x-request-id"),
            HeaderName::from_static("traceparent"),
        ])
        .expose_headers([
            HeaderName::from_static("x-trace-id"),
            HeaderName::from_static("x-request-id"),
        ]);

    let origins: Vec<HeaderValue> = config
        .cors_allowed_origins
        .iter()
        .filter_map(|origin| HeaderValue::from_str(origin).ok())
        .collect();
    if !origins.is_empty() {
        layer = layer.allow_origin(AllowOrigin::list(origins));
    }
    layer
}

/// Content-Length 预检：超限立即 413，不进入 handler。
async fn reject_oversized(req: Request, next: Next, limit: usize) -> Response {
    let oversized = req
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<usize>().ok())
        .is_some_and(|len| len > limit);

    if oversized {
        return (StatusCode::PAYLOAD_TOO_LARGE, "payload too large").into_response();
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use axum::Router;
    use axum::body::Body;
    use axum::http::{Request, StatusCode, header};
    use axum::routing::{get, post};
    use tower::ServiceExt;

    use super::apply_guards;
    use shared::config::HttpConfig;

    fn config() -> HttpConfig {
        HttpConfig {
            body_limit_bytes: 16,
            timeout_secs: 30,
            cors_allowed_origins: Vec::new(),
        }
    }

    fn request(uri: &str) -> Request<Body> {
        // INVARIANT: 测试用静态 URI 为合法请求行。
        Request::builder()
            .uri(uri)
            .body(Body::empty())
            .expect("测试请求构造失败")
    }

    #[tokio::test]
    async fn oversized_content_length_is_rejected() {
        let router = apply_guards(
            Router::new().route("/upload", post(|| async { "ok" })),
            &config(),
        );
        let request = Request::builder()
            .method("POST")
            .uri("/upload")
            .header(header::CONTENT_LENGTH, "32")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = router.oneshot(request).await.expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    }

    #[tokio::test]
    async fn oversized_body_is_rejected_before_method_check() {
        let router = apply_guards(
            Router::new().route("/only-get", get(|| async { "ok" })),
            &config(),
        );
        let request = Request::builder()
            .method("POST")
            .uri("/only-get")
            .header(header::CONTENT_LENGTH, "32")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = router.oneshot(request).await.expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    }

    #[tokio::test]
    async fn within_limit_passes_through() {
        let router = apply_guards(
            Router::new().route("/ping", get(|| async { "pong" })),
            &config(),
        );

        let response = router
            .oneshot(request("/ping"))
            .await
            .expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn slow_handler_returns_408() {
        let mut config = config();
        config.timeout_secs = 1;
        let router = apply_guards(
            Router::new().route(
                "/slow",
                get(|| async {
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    "late"
                }),
            ),
            &config,
        );

        let response = router
            .oneshot(request("/slow"))
            .await
            .expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::REQUEST_TIMEOUT);
    }

    #[tokio::test]
    async fn cors_is_denied_by_default() {
        let router = apply_guards(
            Router::new().route("/ping", get(|| async { "pong" })),
            &config(),
        );
        let request = Request::builder()
            .uri("/ping")
            .header(header::ORIGIN, "https://evil.example")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = router.oneshot(request).await.expect("路由调用失败");
        assert!(
            response
                .headers()
                .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
                .is_none(),
            "未配置白名单时不得回跨域头"
        );
    }

    #[tokio::test]
    async fn cors_allows_configured_origin() {
        let mut config = config();
        config.cors_allowed_origins = vec!["https://app.example.com".to_owned()];
        let router = apply_guards(
            Router::new().route("/ping", get(|| async { "pong" })),
            &config,
        );
        let request = Request::builder()
            .uri("/ping")
            .header(header::ORIGIN, "https://app.example.com")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = router.oneshot(request).await.expect("路由调用失败");
        assert_eq!(
            response
                .headers()
                .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
                .and_then(|value| value.to_str().ok()),
            Some("https://app.example.com")
        );
    }
}
