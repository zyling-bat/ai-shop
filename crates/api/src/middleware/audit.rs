//! 请求审计中间件：响应完成后写一行审计，失败只降级不改变响应。

use std::time::Instant;

use application::audit::AuditEntry;
use axum::extract::{MatchedPath, Request, State};
use axum::middleware::Next;
use axum::response::Response;

use crate::middleware::request_id::RequestId;
use crate::state::AppState;

/// 抓取端点不进入审计，避免抓取频率污染审计表。
const SKIP_PATH: &str = "/metrics";
/// 未匹配路由时原始路径的最大留存长度，防止超长 URI 写入。
const MAX_PATH_LEN: usize = 512;

/// 审计中间件入口。需挂在 `request_id` 之后以取得标识。
pub async fn layer(State(state): State<AppState>, req: Request, next: Next) -> Response {
    let method = req.method().clone();
    let path = match req.extensions().get::<MatchedPath>() {
        Some(matched) => matched.as_str().to_owned(),
        None => truncate_path(req.uri().path()),
    };
    let request_id = req
        .extensions()
        .get::<RequestId>()
        .map(|id| id.as_str().to_owned())
        .unwrap_or_default();

    let started = Instant::now();
    let response = next.run(req).await;
    let latency_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);

    if path == SKIP_PATH {
        return response;
    }

    let entry = AuditEntry {
        trace_id: &request_id,
        request_id: &request_id,
        method: method.as_str(),
        path: &path,
        status: response.status().as_u16(),
        latency_ms,
    };
    if let Err(error) = state.audit.record(entry).await {
        tracing::warn!(error = %error, path = %path, "审计写入失败");
        metrics::counter!("audit_write_failures_total").increment(1);
    }

    response
}

/// 按字符边界截断超长路径。
fn truncate_path(path: &str) -> String {
    if path.len() <= MAX_PATH_LEN {
        return path.to_owned();
    }
    let mut end = MAX_PATH_LEN;
    while !path.is_char_boundary(end) {
        end -= 1;
    }
    path[..end].to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_paths_are_truncated_on_char_boundary() {
        let path = "/".repeat(MAX_PATH_LEN + 10);
        assert_eq!(truncate_path(&path).len(), MAX_PATH_LEN);

        let mixed = format!("{}中", "a".repeat(MAX_PATH_LEN - 1));
        let truncated = truncate_path(&mixed);
        assert_eq!(truncated.len(), MAX_PATH_LEN - 1);
        assert!(truncated.is_char_boundary(truncated.len()));
    }

    #[test]
    fn short_paths_are_kept() {
        assert_eq!(truncate_path("/healthz"), "/healthz");
    }
}
