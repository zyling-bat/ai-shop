# 技术债台账

> 规则（A1）：任何妥协必须写清**原因、影响面、偿还条件**。没有偿还条件的"以后再说"不算登记。
> 编号不复用；偿还后保留条目，状态改为"已偿还"，附偿还 ST 与证据位置。
> 表格列按 `06 §6.8` 固定：`ID | 位置 | 问题 | 影响 | 触发偿还条件 | 负责人 | 登记日期`。

## 待偿还

| ID | 位置 | 状态 | 问题 | 影响 | 触发偿还条件 | 负责人 | 登记日期 |
|---|---|---|---|---|---|---|---|
| TD-003 | `/metrics` 路由 | 待偿还 | 指标端点无鉴权、无抓取侧保护 | 端口直连公网时，路由模板与状态分布可被匿名读取 | ST-0.5 部署清单限制来源（Prometheus 网段 / ingress 白名单）或改独立管理端口，附抓取配置 | 架构 | 2026-11-24 |
| TD-004 | `crates/api/src/router.rs`、`crates/api/src/guards.rs` | 待偿还 | 中间件已落地 `RequestId → Trace → Metrics → CORS → BodyLimit → Timeout → Audit`，但缺 RateLimit / Auth / RBAC / Idempotency | 无认证与权限控制、无限流与幂等保护；当前仅只读探针接口，风险可接受 | Auth / RBAC / Idempotency 随 P2 / P5 落地，RateLimit 按接口写入压力在 P2 评估；每步附 Gate 证据 | 架构 | 2026-11-24 |
| TD-005 | `crates/api/src/middleware/audit.rs`、`migrations/*_audit_log.*` | 待偿还 | 所有路径（`/metrics` 除外）逐请求同步写审计，探针请求同样留痕 | 生产探针频率会放大 `audit_log` 行数与写入延迟；单请求多一次 INSERT | P2 审计模块落地时按策略采样、排除 `/healthz`、`/readyz`，并评估批量/异步写入；需保留 P0-5 的可验证证据后再调整 | 架构 | 2026-11-24 |
| TD-006 | `crates/infrastructure/src/{db,audit}.rs`、CI | 待偿还 | 本轮使用运行时 SQL（`query` / `query_scalar`），未接 `sqlx::query!` 编译期校验与 `.sqlx/` 离线元数据 | 字段/类型错误只能在运行期暴露；CI 未校验 SQL 与 schema 一致性 | 首个业务表查询的 ST（P1）起改用编译期查询，`.sqlx/` 入库并在 CI 设置 `SQLX_OFFLINE=true` 构建 | 架构 | 2026-11-24 |

## 已偿还

| ID | 位置 | 偿还 ST | 证据 |
|---|---|---|---|
| TD-001 | `apps/server/src/telemetry.rs`、`crates/api/src/middleware/{trace,propagation}.rs`、ADR-008 §5 | ST-0.4 | `opentelemetry 0.27` + `opentelemetry_sdk 0.27` + `tracing-opentelemetry 0.28` 已接入；`OTEL_EXPORTER_OTLP_ENDPOINT` 非空时挂 OTLP(gRPC) 导出器，为空时仅本地生成 trace；`cargo test --workspace` 61 passed；运行态 `otlp_export=false` 启动正常、`otlp_export=true` 时导出失败不致命（`docs/gates/P0.md` §六）。后端检索待具备 collector 时补证据（ADR-008 §5 采集边界）。 |
| TD-002 | `crates/api/src/middleware/trace.rs`、`crates/api/src/middleware/audit.rs` | ST-0.4 | `trace_id` 改为 OTel span context 的 32 位十六进制，`request_id` 保持 UUID v7 / 入站值；入站合法 `traceparent` 续接、非法/缺失新建；日志与 `audit_log` 同源（实测 `4bf92f3577b34da6a3ce929d0e0e4736` 贯穿响应头、日志与 DB，见 `docs/gates/P0.md` §六）。 |
