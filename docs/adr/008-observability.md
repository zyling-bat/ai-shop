# ADR-008 可观测口径：日志、指标与 trace 串联

- 状态：已接受（Accepted）
- 日期：2026-11-24
- 阶段：P0 / ST-0.2（初版）；ST-0.4 更新为真 OTel 口径
- 关联约束：A4（tracing + OTel + Prometheus）、C4（日志统一走 tracing）、C11（禁止无上限/高基数查询，指标标签同理）、C24（AI 调用日志含 trace_id）、C28（日志脱敏）、06 §6.3.6（中间件顺序）、06 §6.4（配置项）、05 §5.1 P0 Gate 第 4/5 条

## 背景

ST-0.1 的进程只有默认 `info` 文本日志：没有请求标识、没有耗时、没有指标。P0 Gate 第 4 条（`/metrics` 两个指标）与第 5 条（一次请求串起 `trace_id`）没有任何承载物，后续每个 ST 的"自证"都会退化成加临时打印。

ST-0.2 先落了 `request_id` 与 Prometheus 指标，并把 `trace_id` 暂设为 `request_id` 同值（当时的过渡态）。ST-0.4 引入 OTel SDK 与 `tracing-opentelemetry` 桥接，`trace_id` 改为真正的 W3C trace 上下文，可入站续接、可跨进程传播。

## 决策

### 1. 日志

- 统一 `tracing` + `tracing-subscriber`（`env-filter` + `json`），禁止 `println!/eprintln!`（workspace lint 已 deny）。
- 格式二选一：`LOG_FORMAT=pretty|json`；默认值随 `APP_ENV`（`prod` → `json`，其余 → `pretty`）。
- 过滤：`RUST_LOG`，默认 `info,sqlx=warn`。
- 日志字段禁止出现：密钥、完整手机号/证件号/银行卡、请求体、`Authorization` 头（C28）。`JwtConfig` 的 `Debug` 手写为 `<redacted>`。

### 2. 关联标识（真 OTel trace）

- 每个请求一个 `request_id`：入站 `X-Request-Id` 合法（`[A-Za-z0-9._-]{1,64}`）则沿用，否则生成 UUID v7；语义是业务侧关联键。
- 每个请求同时携带 W3C trace 上下文：`trace_id` 为 32 位小写十六进制，由 OTel SDK 生成。
- 入站 `traceparent` 严格合法（`00-<32hex>-<16hex>-<2hex>`，长度 55、全小写十六进制、trace/span 非全零）则作为父上下文续接；缺失或非法一律新建，不报错。
- 响应头：`X-Request-Id` 回写请求标识；`x-trace-id` 只回 trace id（不回完整 `traceparent`，避免误导调用方可以续接）。
- 日志 `http_request` span 同时含 `trace_id` 与 `request_id`，两者取值不同；DB 审计表 `audit_log` 落同一 `trace_id`。

### 3. 指标

- 门面 `metrics 0.24`，导出 `metrics-exporter-prometheus 0.16`，**`default-features = false`**：只用 recorder，不用内建 HTTP listener / push gateway（否则引入 hyper + rustls + aws-lc-sys，编译时间与攻击面都不划算）。暴露由 axum 的 `GET /metrics` 承担。
- 指标清单：

| 指标 | 类型 | 标签 | 说明 |
|---|---|---|---|
| `http_requests_total` | counter | `method` / `path` / `status` | 请求总数 |
| `http_request_duration_seconds` | histogram | `method` / `path` | 请求耗时，分桶 1ms~10s |

- 命名注意：`metrics-exporter-prometheus 0.16` **不会**自动补 `_total`，counter 名称必须自带该后缀，否则 P0 Gate 断言不成立（已实测：命名为 `http_requests` 时渲染为 `http_requests`）。
- `path` 必须取 axum `MatchedPath`（路由模板），未命中路由记 `unmatched`；禁止原始 URI、禁止查询串，防标签基数爆炸（C11 同源要求）。
- `/metrics` 自身抓取不计数，避免抓取频率污染业务口径。
- 分桶覆盖毫秒级到 10s；P16 压测后如需要再按 P95 目标调整。

### 4. 中间件顺序

已落地 `RequestId → Trace(OTel) → Metrics → CORS → BodyLimit → Timeout → Audit → Handler`，与 06 §6.3.6 一致。护栏参数来自 `HTTP_BODY_LIMIT_BYTES` / `HTTP_TIMEOUT_SECS` / `CORS_ALLOWED_ORIGINS`；RateLimit / Auth / RBAC / Idempotency 在后续 ST 按同表插入，不得重排。

### 5. OTel 接入（ST-0.4 已落地）

- `opentelemetry 0.27` + `opentelemetry_sdk 0.27` + `tracing-opentelemetry 0.28` 桥接现有 `tracing` span，字段名不变。
- 导出器：`OTEL_EXPORTER_OTLP_ENDPOINT` 非空时挂 `opentelemetry-otlp 0.27`（`grpc-tonic`，默认 4317）批量导出；为空时只构造本地 TracerProvider，trace id 照常生成，不导出。
- 装配位置：`apps/server/src/telemetry.rs`，在绑定端口前完成；导出器构造失败直接退出（退出码 4），不静默降级。进程退出前调用 `TracerProvider::shutdown` 冲刷队列。
- 采集边界：本机无 collector，OTLP 端到端只验证"代码就位 + `otlp_export=true` + 导出失败不致命"；后端检索待具备 collector 时补证据。
- 采样：P0/P1 全量；P16 起按 10% 头部采样 + 错误全采。

## 后果

- 好处：请求可凭 `X-Request-Id` 定位业务链路，凭 `trace_id` 关联跨进程 trace；`/metrics` 满足 Gate；入站 `traceparent` 可直接续接，P5 出站调用只需注入同一上下文即可打通。
- 代价：新增 OTel 依赖（`opentelemetry-otlp` 的 gRPC 栈会拉长首次全量编译）；无 collector 时导出失败会周期性打 error 日志，需在部署时配置端点或保持未设置。
- 风险：指标标签若被误改为原始 URI，会造成 Prometheus 基数爆炸。缓解：标签只从 `MatchedPath` 取，代码评审检查；后续可加基数上限断言。CORS 默认全拒，P14 前端联调前必须配置 `CORS_ALLOWED_ORIGINS`。

## 备选方案

| 方案 | 为何不选 |
|---|---|
| `tower-http` 的 `TraceLayer` | 默认 span 无法注入自有 `request_id` / `trace_id`；自研 trace 已带低基数标签，不重复建设 |
| `prometheus` crate 直接埋点 | 不在 06 §6.1 锁版清单；宏式门面换成全局注册表会污染业务代码 |
| 自研 Prometheus 文本导出 | 等于重写 exporter，分桶/转义/并发都是坑 |
| OTLP 用 `http-proto` | 已确认走 `grpc-tonic`（4317），与后续 collector 默认端口一致 |
| ST-0.2 直接接 OTel SDK | 当时无依赖锁版批准且无 collector，先以 `request_id` 过渡；ST-0.4 已在批准后补齐 |

## 验证

- P0 Gate 第 4 条：`curl.exe -s http://127.0.0.1:8080/metrics` 含 `http_requests_total{...}` 与 `http_request_duration_seconds_bucket{...}`。
- P0 Gate 第 5 条（服务段）：同一请求的日志含 `request_id` / `trace_id`，响应头 `x-trace-id` 与日志 `trace_id` 一致；带合法 `traceparent` 时沿用其 trace id。
- 证据：`docs/gates/P0.md` §三、§六。
