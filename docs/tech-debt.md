# 技术债台账

> 规则（A1）：任何妥协必须写清**原因、影响面、偿还条件**。没有偿还条件的"以后再说"不算登记。
> 编号不复用；偿还后保留条目，状态改为"已偿还"，附偿还 ST 与证据位置。
> 表格列按 `06 §6.8` 固定：`ID | 位置 | 问题 | 影响 | 触发偿还条件 | 负责人 | 登记日期`。

## 待偿还

| ID | 位置 | 状态 | 问题 | 影响 | 触发偿还条件 | 负责人 | 登记日期 |
|---|---|---|---|---|---|---|---|
| TD-001 | `apps/server`、`api` 中间件、`docs/adr/008` | 待偿还 | OTel SDK / OTLP 导出未接入；P0 只有本地 `tracing` 日志与 Prometheus | 无跨进程 trace 传播、无 span 树、无 trace 后端检索；`trace_id` 暂等于 `request_id`（TD-002） | ST-0.4 引入 `opentelemetry` / `opentelemetry-otlp` + `tracing-opentelemetry`，保留现有日志字段名，补"请求 → span → 后端可查"证据 | 架构 | 2026-11-24 |
| TD-002 | `crates/api/src/middleware/trace.rs`、`audit` | 待偿还 | `trace_id` 暂由 `request_id` 承担 | 审计与 AI 调用日志无法跨服务关联；对 C24 同样成立 | 随 TD-001 改为 SDK 生成的 32 位十六进制 trace id，`request_id` 保留为业务关联键，两者同时入日志，并更新 ADR-008 §2 | 架构 | 2026-11-24 |
| TD-003 | `/metrics` 路由 | 待偿还 | 指标端点无鉴权、无抓取侧保护 | 端口直连公网时，路由模板与状态分布可被匿名读取 | ST-0.5 部署清单限制来源（Prometheus 网段 / ingress 白名单）或改独立管理端口，附抓取配置 | 架构 | 2026-11-24 |
| TD-004 | `crates/api/src/router.rs` | 待偿还 | 中间件仅落地 `RequestId → Trace → Metrics → Audit` 四层 | 无 BodyLimit / Timeout / CORS / RateLimit / Auth / Idempotency；当前仅只读短请求，风险可接受 | ST-0.4 按 06 §6.3.6 补 BodyLimit / Timeout / CORS；Auth / RBAC / Idempotency 随 P2 / P5，每步附 Gate 证据 | 架构 | 2026-11-24 |
| TD-005 | `crates/api/src/middleware/audit.rs`、`migrations/*_audit_log.*` | 待偿还 | 所有路径（`/metrics` 除外）逐请求同步写审计，探针请求同样留痕 | 生产探针频率会放大 `audit_log` 行数与写入延迟；单请求多一次 INSERT | P2 审计模块落地时按策略采样、排除 `/healthz`、`/readyz`，并评估批量/异步写入；需保留 P0-5 的可验证证据后再调整 | 架构 | 2026-11-24 |
| TD-006 | `crates/infrastructure/src/{db,audit}.rs`、CI | 待偿还 | 本轮使用运行时 SQL（`query` / `query_scalar`），未接 `sqlx::query!` 编译期校验与 `.sqlx/` 离线元数据 | 字段/类型错误只能在运行期暴露；CI 未校验 SQL 与 schema 一致性 | 首个业务表查询的 ST（P1）起改用编译期查询，`.sqlx/` 入库并在 CI 设置 `SQLX_OFFLINE=true` 构建 | 架构 | 2026-11-24 |

## 已偿还

| ID | 位置 | 偿还 ST | 证据 |
|---|---|---|---|
| — | — | — | — |
