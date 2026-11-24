//! 路由装配：ST-0.1 只暴露存活探针 `/healthz`。

use axum::Router;
use axum::routing::get;

/// 构造对外路由表。当前仅含 `GET /healthz`，业务路由与 `/readyz`、`/metrics` 留待后续 ST。
pub fn router() -> Router {
    Router::new().route("/healthz", get(healthz))
}

async fn healthz() -> &'static str {
    "ok"
}

#[cfg(test)]
mod tests {
    use axum::body::{Body, to_bytes};
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    use super::router;

    fn request(uri: &str) -> Request<Body> {
        // INVARIANT: 测试用静态 URI 均为合法请求行，构造失败只可能是 URI 字面量被改坏。
        Request::builder()
            .uri(uri)
            .body(Body::empty())
            .expect("测试请求构造失败")
    }

    #[tokio::test]
    async fn healthz_returns_200_ok() {
        let response = router()
            .oneshot(request("/healthz"))
            .await
            .expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("读取响应体失败");
        assert_eq!(&body[..], b"ok");
    }

    #[tokio::test]
    async fn readyz_is_not_implemented() {
        let response = router()
            .oneshot(request("/readyz"))
            .await
            .expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }
}
