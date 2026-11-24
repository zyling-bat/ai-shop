//! HTTP 中间件：请求标识、请求日志、指标采集与请求审计。
//!
//! 装配顺序见 06 §6.3.6：
//! `RequestId → Trace → Metrics → CORS → BodyLimit → Timeout → Audit → Handler`。
//! CORS / BodyLimit / Timeout 三层护栏在 [`crate::guards`] 中装配。

pub mod audit;
pub mod metrics;
pub mod propagation;
pub mod request_id;
pub mod trace;

pub use propagation::{TRACE_ID_HEADER, TraceId};
pub use request_id::{REQUEST_ID_HEADER, RequestId};
