//! `GET /readyz`：逐项报告依赖就绪状态。

use application::health::{ProbeReport, all_up};
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use serde::Serialize;

use crate::state::AppState;

#[derive(Serialize)]
struct ReadyzBody {
    status: &'static str,
    probes: Vec<ProbeView>,
}

#[derive(Serialize)]
struct ProbeView {
    name: &'static str,
    status: &'static str,
    latency_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl From<ProbeReport> for ProbeView {
    fn from(report: ProbeReport) -> Self {
        Self {
            name: report.name,
            status: report.status.as_str(),
            latency_ms: report.latency_ms,
            error: report.error,
        }
    }
}

/// 全部探针 up 且非空 → 200；否则 503（不伪装成功）。
pub async fn readyz(State(state): State<AppState>) -> impl IntoResponse {
    let reports = state.readiness.check().await;
    let ready = all_up(&reports);
    let body = ReadyzBody {
        status: if ready { "ready" } else { "not_ready" },
        probes: reports.into_iter().map(ProbeView::from).collect(),
    };
    let code = if ready {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (code, Json(body))
}
