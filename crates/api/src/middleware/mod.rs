//! HTTP 中间件：请求标识、请求日志、指标采集与请求审计。
//!
//! 装配顺序见 06 §6.3.6：`RequestId → Trace → Metrics → Audit → Handler`。
//! 本轮只落地这四层；CORS / BodyLimit / Timeout / RateLimit / Auth / Idempotency
//! 在后续 ST 按同一顺序补齐。

pub mod audit;
pub mod metrics;
pub mod request_id;
pub mod trace;

pub use request_id::{REQUEST_ID_HEADER, RequestId};
