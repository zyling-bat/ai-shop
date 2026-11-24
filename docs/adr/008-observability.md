# ADR-008 可观测口径：日志、指标与 trace 串联

- 状态：已接受（Accepted）
- 日期：2026-11-24
- 阶段：P0 / ST-0.2
- 关联约束：A4（tracing + OTel + Prometheus）、C4（日志统一走 tracing）、C11（禁止无上限/高基数查询，指标标签同理）、C24（AI 调用日志含 trace_id）、C28（日志脱敏）、06 §6.3.6（中间件顺序）、06 §6.4（配置项）、05 §5.1 P0 Gate 第 4/5 条

## 背景

ST-0.1 的进程只有默认 `info` 文本日志：没有请求标识、没有耗时、没有指标。P0 Gate 第 4 条（`/metrics` 两个指标）与第 5 条（一次请求串起 `trace_id`）没有任何承载物，后续每个 ST 的"自证"都会退化成加临时打印。

同时有个必须提前定死的取舍：**OTel SDK 一旦引入，`trace_id` 由 SDK 生成并随导出器传播**；而 P0 阶段没有 collector、没有 compose（ST-0.3 才有）。若本轮硬接 OTel，只能验证"代码编译过"，无法验证链路，反而制造"看起来接好了"的假象。

## 决策

### 1. 日志

- 统一 `tracing` + `tracing-subscriber`（`env-filter` + `json`），禁止 `println!/eprintln!`（workspace lint 已 deny）。
- 格式二选一：`LOG_FORMAT=pretty|json`；默认值随 `APP_ENV`（`prod` → `json`，其余 → `pretty`）。
- 过滤：`RUST_LOG`，默认 `info,sqlx=warn`。
- 日志字段禁止出现：密钥、完整手机号/证件号/银行卡、请求体、`Authorization` 头（C28）。`JwtConfig` 的 `Debug` 手写为 `<redacted>`。

### 2. 关联标识（P0 过渡态）

- 每个请求一个标识：入站 `X-Request-Id` 合法（`[A-Za-z0-9._-]{1,64}`）则沿用，否则生成 UUID v7。
- 该值写入：请求扩展、响应头 `X-Request-Id`、`http_request` span 的 `request_id` 与 `trace_id` 字段。
- **P0 阶段 `trace_id` 与 `request_id` 同值**：没有 OTel SDK 就没有独立的 trace 语义，强行区分只会产生"两个都对不上"的假象。ST-0.3 接入 SDK 后，`trace_id` 由 SDK 生成并随 `traceparent` 传播，`request_id` 继续作为业务侧关联键。
- DB 审计表（ST-0.3 建表）落同名列 `trace_id`，P0 Gate 第 5 条的"DB 审计"段届时闭合。

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

本轮落地 `RequestId → Trace → Metrics → Handler`，与 06 §6.3.6 的相对次序一致；CORS / BodyLimit / Timeout / RateLimit / Auth / RBAC / Idempotency 在后续 ST 按同表插入，不得重排。

### 5. OTel 的接入路径（未做，明确偿还）

- ST-0.3：compose 起 collector，引入 `opentelemetry` / `opentelemetry-otlp`，`tracing-opentelemetry` 桥接现有 span，**保持现有字段名不变**，使日志与 trace 后端用同一套键能互相跳转。
- 接入时保留 `request_id`，`trace_id` 改为 SDK 值；两者同时出现在日志中，便于按老口径检索历史。
- 采样：P0/P1 全量；P16 起按 10% 头部采样 + 错误全采。

## 后果

- 好处：任何一个请求都能凭 `X-Request-Id` 在日志里定位；`/metrics` 直接满足 Gate；后续接 OTel 时字段稳定，不需要改日志消费方。
- 代价：`trace_id` 暂时不是真正的分布式 trace，跨服务/跨进程不可传播；已登记 `docs/tech-debt.md`。
- 风险：指标标签若被误改为原始 URI，会造成 Prometheus 基数爆炸。缓解：标签只从 `MatchedPath` 取，代码评审检查；后续可加基数上限断言。

## 备选方案

| 方案 | 为何不选 |
|---|---|
| `tower-http` 的 `TraceLayer` | 默认 span 无法注入自有 `request_id`，需要额外拼装；且本轮不引入 tower-http，减少依赖面 |
| `prometheus` crate 直接埋点 | 不在 06 §6.1 锁版清单；宏式门面换成全局注册表会污染业务代码 |
| 自研 Prometheus 文本导出 | 等于重写 exporter，分桶/转义/并发都是坑 |
| 本轮直接接 OTel SDK | 无 collector 可验证，只能"编译过"；且 P0 Gate 不要求 OTLP 导出 |

## 验证

- P0 Gate 第 4 条：`curl.exe -s http://127.0.0.1:8080/metrics` 含 `http_requests_total{...}` 与 `http_request_duration_seconds_bucket{...}`。
- P0 Gate 第 5 条（服务段）：同一请求的 JSON 日志含 `request_id` / `trace_id`，且与响应头 `X-Request-Id` 一致。
- 证据：`docs/gates/P0.md` §三。
