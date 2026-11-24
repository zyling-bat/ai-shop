//! API 层：路由、中间件与协议转换。

pub mod guards;
pub mod handlers;
pub mod middleware;
pub mod router;
pub mod state;

pub use router::router;
pub use state::AppState;
