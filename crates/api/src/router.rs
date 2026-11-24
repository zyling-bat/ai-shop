//! 路由装配：存活 / 就绪探针、指标抓取，以及请求标识 / 日志 / 指标 / 审计中间件。

use axum::Router;
use axum::middleware::{from_fn, from_fn_with_state};
use axum::routing::get;
use tower::ServiceBuilder;

use crate::guards;
use crate::handlers::readyz::readyz;
use crate::middleware::{audit, metrics, request_id, trace};
use crate::state::AppState;

/// 构造对外路由表。
///
/// 中间件顺序按 06 §6.3.6：
/// `RequestId → Trace → Metrics → CORS → BodyLimit → Timeout → Audit → Handler`。
/// 审计依赖 `request_id` / `trace_id` 扩展，因此必须排在它们之后；
/// 护栏排在审计之前，保证被拒绝的请求仍被计数与审计。
pub fn router(state: AppState) -> Router {
    let audited = Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/metrics", get(metrics::scrape))
        .layer(from_fn_with_state(state.clone(), audit::layer));

    guards::apply_guards(audited, &state.http)
        .layer(
            ServiceBuilder::new()
                .layer(from_fn(request_id::layer))
                .layer(from_fn(trace::layer))
                .layer(from_fn(metrics::layer)),
        )
        .with_state(state)
}

async fn healthz() -> &'static str {
    "ok"
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex, OnceLock};

    use application::audit::{AuditEntry, AuditError, AuditSink};
    use application::health::{HealthProbe, Readiness};
    use async_trait::async_trait;
    use axum::body::{Body, to_bytes};
    use axum::http::{Request, StatusCode, header};
    use metrics_exporter_prometheus::PrometheusHandle;
    use opentelemetry::trace::TracerProvider as _;
    use opentelemetry_sdk::trace::TracerProvider;
    use shared::config::HttpConfig;
    use tower::ServiceExt;
    use tracing_subscriber::layer::SubscriberExt;

    use super::router;
    use crate::middleware::metrics;
    use crate::state::AppState;

    /// 装配带 OTel 层的订阅器（进程内一次），使 `trace_id` 由 SDK 生成。
    fn install_tracing() {
        static PROVIDER: OnceLock<TracerProvider> = OnceLock::new();
        static INIT: OnceLock<()> = OnceLock::new();
        INIT.get_or_init(|| {
            let provider = PROVIDER
                .get_or_init(|| TracerProvider::builder().build())
                .clone();
            let subscriber = tracing_subscriber::registry()
                .with(tracing_opentelemetry::layer().with_tracer(provider.tracer("api-tests")));
            // INVARIANT: 测试进程内只装配一次全局订阅器。
            tracing::subscriber::set_global_default(subscriber).expect("测试期装配订阅器失败");
        });
    }

    /// 进程内唯一记录器：`install` 只能成功一次，测试间共享同一份计数。
    fn handle() -> PrometheusHandle {
        static HANDLE: OnceLock<PrometheusHandle> = OnceLock::new();
        HANDLE
            .get_or_init(|| {
                metrics::install()
                    // INVARIANT: 测试进程内首次安装记录器，失败说明指标装配有误，必须暴露。
                    .expect("测试期安装 Prometheus 记录器失败")
            })
            .clone()
    }

    struct FixedProbe {
        name: &'static str,
        ok: bool,
    }

    #[async_trait]
    impl HealthProbe for FixedProbe {
        fn name(&self) -> &'static str {
            self.name
        }

        async fn check(&self) -> Result<(), String> {
            if self.ok {
                Ok(())
            } else {
                Err("不可用".to_owned())
            }
        }
    }

    fn probe(name: &'static str, ok: bool) -> Arc<dyn HealthProbe> {
        Arc::new(FixedProbe { name, ok })
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    struct Recorded {
        trace_id: String,
        request_id: String,
        method: String,
        path: String,
        status: u16,
    }

    #[derive(Clone, Default)]
    struct RecordingSink {
        entries: Arc<Mutex<Vec<Recorded>>>,
    }

    impl RecordingSink {
        fn entries(&self) -> Vec<Recorded> {
            // INVARIANT: 测试内锁未被毒化；持有期间不做 await。
            self.entries.lock().expect("审计记录锁被毒化").clone()
        }
    }

    #[async_trait]
    impl AuditSink for RecordingSink {
        async fn record(&self, entry: AuditEntry<'_>) -> Result<(), AuditError> {
            self.entries
                .lock()
                // INVARIANT: 同上。
                .expect("审计记录锁被毒化")
                .push(Recorded {
                    trace_id: entry.trace_id.to_owned(),
                    request_id: entry.request_id.to_owned(),
                    method: entry.method.to_owned(),
                    path: entry.path.to_owned(),
                    status: entry.status,
                });
            Ok(())
        }
    }

    struct FailingSink;

    #[async_trait]
    impl AuditSink for FailingSink {
        async fn record(&self, _entry: AuditEntry<'_>) -> Result<(), AuditError> {
            Err(AuditError::unavailable(std::io::Error::other(
                "模拟审计存储不可用",
            )))
        }
    }

    fn state_with_config(
        probes: Vec<Arc<dyn HealthProbe>>,
        audit: Arc<dyn AuditSink>,
        http: HttpConfig,
    ) -> AppState {
        AppState::new(handle(), Arc::new(Readiness::new(probes)), audit, http)
    }

    fn state_with(probes: Vec<Arc<dyn HealthProbe>>, audit: Arc<dyn AuditSink>) -> AppState {
        state_with_config(probes, audit, HttpConfig::default())
    }

    fn app_with(probes: Vec<Arc<dyn HealthProbe>>, audit: Arc<dyn AuditSink>) -> axum::Router {
        router(state_with(probes, audit))
    }

    fn app_with_config(
        probes: Vec<Arc<dyn HealthProbe>>,
        audit: Arc<dyn AuditSink>,
        http: HttpConfig,
    ) -> axum::Router {
        router(state_with_config(probes, audit, http))
    }

    fn app() -> axum::Router {
        app_with(
            vec![probe("postgres", true), probe("redis", true)],
            Arc::new(RecordingSink::default()),
        )
    }

    fn request(uri: &str) -> Request<Body> {
        // INVARIANT: 测试用静态 URI 均为合法请求行，构造失败只可能是 URI 字面量被改坏。
        Request::builder()
            .uri(uri)
            .body(Body::empty())
            .expect("测试请求构造失败")
    }

    fn request_with_id(uri: &str, request_id: &str) -> Request<Body> {
        // INVARIANT: 同上；请求标识为测试常量。
        Request::builder()
            .uri(uri)
            .header("x-request-id", request_id)
            .body(Body::empty())
            .expect("测试请求构造失败")
    }

    async fn send(app: axum::Router, uri: &str) -> axum::response::Response {
        app.oneshot(request(uri)).await.expect("路由调用失败")
    }

    async fn body_text(response: axum::response::Response) -> String {
        let bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("读取响应体失败");
        String::from_utf8(bytes.to_vec()).expect("响应体应为 UTF-8")
    }

    /// 从 Prometheus 文本中取指定标签组合的 counter 值，缺失时返回 0。
    fn counter_value(text: &str, path: &str, status: &str) -> f64 {
        text.lines()
            .filter(|line| line.starts_with("http_requests_total{"))
            .find(|line| {
                line.contains(&format!("path=\"{path}\""))
                    && line.contains(&format!("status=\"{status}\""))
            })
            .and_then(|line| line.rsplit(' ').next())
            .and_then(|value| value.parse().ok())
            .unwrap_or(0.0)
    }

    #[tokio::test]
    async fn healthz_returns_200_ok() {
        let response = send(app(), "/healthz").await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(body_text(response).await, "ok");
    }

    #[tokio::test]
    async fn readyz_reports_all_up() {
        let response = send(app(), "/readyz").await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = body_text(response).await;
        let json: serde_json::Value = serde_json::from_str(&body).expect("readyz 应为 JSON");
        assert_eq!(json["status"], "ready");
        assert_eq!(json["probes"][0]["name"], "postgres");
        assert_eq!(json["probes"][0]["status"], "up");
        assert_eq!(json["probes"][1]["name"], "redis");
    }

    #[tokio::test]
    async fn readyz_is_503_when_a_probe_is_down() {
        let app = app_with(
            vec![probe("postgres", true), probe("redis", false)],
            Arc::new(RecordingSink::default()),
        );
        let response = send(app, "/readyz").await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);

        let body = body_text(response).await;
        let json: serde_json::Value = serde_json::from_str(&body).expect("readyz 应为 JSON");
        assert_eq!(json["status"], "not_ready");
        assert_eq!(json["probes"][1]["status"], "down");
        assert_eq!(json["probes"][1]["error"], "不可用");
    }

    #[tokio::test]
    async fn readyz_without_probes_is_not_ready() {
        let app = app_with(Vec::new(), Arc::new(RecordingSink::default()));
        let response = send(app, "/readyz").await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);

        let body = body_text(response).await;
        let json: serde_json::Value = serde_json::from_str(&body).expect("readyz 应为 JSON");
        assert_eq!(json["status"], "not_ready");
        assert_eq!(json["probes"].as_array().map(Vec::len), Some(0));
    }

    #[tokio::test]
    async fn metrics_exposes_required_series() {
        let app = app();
        // 先制造两次被计数的请求，再抓取。
        assert_eq!(send(app.clone(), "/healthz").await.status(), StatusCode::OK);
        assert_eq!(send(app.clone(), "/healthz").await.status(), StatusCode::OK);

        let response = send(app, "/metrics").await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response
                .headers()
                .get(header::CONTENT_TYPE)
                .and_then(|value| value.to_str().ok()),
            Some("text/plain; version=0.0.4")
        );

        let body = body_text(response).await;
        assert!(
            body.contains("http_requests_total{"),
            "缺少 http_requests_total：{body}"
        );
        assert!(
            body.contains("http_request_duration_seconds_bucket"),
            "缺少 http_request_duration_seconds：{body}"
        );
        assert!(
            counter_value(&body, "/healthz", "200") >= 2.0,
            "/healthz 计数未累加：{body}"
        );
        assert!(
            !body.contains("path=\"/metrics\""),
            "抓取 /metrics 不得自我计数：{body}"
        );
    }

    #[tokio::test]
    async fn audit_records_request_metadata() {
        install_tracing();
        let sink = Arc::new(RecordingSink::default());
        let app = app_with(vec![probe("postgres", true)], sink.clone());

        let response = app
            .oneshot(request_with_id("/healthz", "p0-trace-001"))
            .await
            .expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::OK);

        let entries = sink.entries();
        assert_eq!(entries.len(), 1);
        let entry = &entries[0];
        assert_eq!(entry.request_id, "p0-trace-001");
        assert_eq!(entry.method, "GET");
        assert_eq!(entry.path, "/healthz");
        assert_eq!(entry.status, 200);
        assert!(is_trace_id(&entry.trace_id), "trace_id 应为 32 位十六进制");
        assert_ne!(
            entry.trace_id, entry.request_id,
            "trace_id 必须独立于 request_id"
        );
    }

    #[tokio::test]
    async fn traceparent_is_continued() {
        install_tracing();
        let traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
        let sink = Arc::new(RecordingSink::default());
        let app = app_with(vec![probe("postgres", true)], sink.clone());
        let request = Request::builder()
            .uri("/healthz")
            .header("traceparent", traceparent)
            .body(Body::empty())
            // INVARIANT: 测试用静态 URI 与头部为合法字面量。
            .expect("测试请求构造失败");

        let response = app.oneshot(request).await.expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response
                .headers()
                .get("x-trace-id")
                .and_then(|value| value.to_str().ok()),
            Some("4bf92f3577b34da6a3ce929d0e0e4736")
        );

        let entries = sink.entries();
        assert_eq!(entries[0].trace_id, "4bf92f3577b34da6a3ce929d0e0e4736");
        assert_ne!(entries[0].request_id, entries[0].trace_id);
    }

    #[tokio::test]
    async fn invalid_traceparent_is_ignored() {
        install_tracing();
        let app = app();
        let request = Request::builder()
            .uri("/healthz")
            .header("traceparent", "00-bad")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = app.oneshot(request).await.expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::OK);
        let trace_id = response
            .headers()
            .get("x-trace-id")
            .and_then(|value| value.to_str().ok())
            .expect("响应必须带 x-trace-id");
        assert!(
            is_trace_id(trace_id),
            "应生成新的 32 位 trace id：{trace_id}"
        );
        assert_ne!(trace_id, "00-bad");
    }

    #[tokio::test]
    async fn oversized_request_is_counted() {
        let app = app_with_config(
            vec![probe("postgres", true)],
            Arc::new(RecordingSink::default()),
            HttpConfig {
                body_limit_bytes: 16,
                ..HttpConfig::default()
            },
        );
        let request = Request::builder()
            .method("POST")
            .uri("/healthz")
            .header(header::CONTENT_LENGTH, "32")
            .body(Body::empty())
            // INVARIANT: 同上。
            .expect("测试请求构造失败");

        let response = app.clone().oneshot(request).await.expect("路由调用失败");
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);

        let body = body_text(send(app, "/metrics").await).await;
        assert!(
            counter_value(&body, "/healthz", "413") >= 1.0,
            "413 应被 Metrics 计数：{body}"
        );
    }

    /// 32 位小写十六进制校验。
    fn is_trace_id(value: &str) -> bool {
        value.len() == 32
            && value
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    }

    #[tokio::test]
    async fn audit_skips_metrics_scrape() {
        let sink = Arc::new(RecordingSink::default());
        let app = app_with(vec![probe("postgres", true)], sink.clone());

        assert_eq!(send(app, "/metrics").await.status(), StatusCode::OK);
        assert!(sink.entries().is_empty(), "/metrics 不应写入审计");
    }

    #[tokio::test]
    async fn audit_failure_does_not_change_response() {
        let app = app_with(vec![probe("postgres", true)], Arc::new(FailingSink));

        let response = send(app, "/healthz").await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(body_text(response).await, "ok");
    }
}
