# ST-0.4 OpenTelemetry 接入与请求护栏中间件 Spec

> 阶段：P0 工程基座｜本轮只做 ST-0.4：把"伪 `trace_id`"换成 OTel SDK 生成的真 trace，补齐 06 §6.3.6 中的 CORS / BodyLimit / Timeout 三层护栏，并偿还 TD-001 / TD-002 / TD-004。
> 依据：`06-工程执行清单.md`（6.1 依赖锁版、6.3.6 中间件顺序、6.4 配置项、6.5 改动边界）、`05-验收用例与Gate.md`（§5.1 P0-5）、`00-总纲与主Prompt.md`（C4/C6/C11/C24/C28）、`docs/adr/008-observability.md` §2/§5、`docs/tech-debt.md` TD-001/TD-002/TD-004。

## Why

ST-0.2 用一个权宜之计闭合了 P0-5：`trace_id` 直接复用 `request_id`（ADR-008 §2 明确标注"P0 过渡态"）。这带来两个真实缺陷：

1. **跨进程不可关联**：`trace_id` 是 36 位 UUID，不是分布式 trace 语义；任何出站调用（P5 支付、P11 AI 网关、P12 渠道回调）都没有可传播的父上下文，C24 要求的"AI 调用日志含 trace_id"到了 P11 只能重新改造。
2. **入站链路无法续接**：调用方带 `traceparent` 时服务端视而不见，链路在网关处断掉。

同时 TD-004 记录着：当前只有 `RequestId → Trace → Metrics → Audit` 四层，缺少 BodyLimit / Timeout / CORS。P0 只有只读短请求，风险可控；但 P2 一旦出现登录、下单等写接口，没有请求体上限与超时就是可被利用的资源耗尽面。

本 ST 只解决这两件事：**让 `trace_id` 变成真正的 W3C trace 上下文并可在进程间传播**，**把无状态的请求护栏按 06 §6.3.6 固定顺序补上**。不写业务表、不写业务路由。

## What Changes

- `shared::config` 新增：
  - `TelemetryConfig`：`OTEL_SERVICE_NAME`（默认 `ecom-server`）、`OTEL_EXPORTER_OTLP_ENDPOINT`（可选；为空则不安装导出器，仅本地生成 trace）
  - `HttpConfig`：`HTTP_BODY_LIMIT_BYTES`（默认 `2097152`）、`HTTP_TIMEOUT_SECS`（默认 `30`）、`CORS_ALLOWED_ORIGINS`（逗号分隔，默认空 = 不放行任何跨域来源）
- `apps/server` 新增 `telemetry.rs`：装配 `tracing-subscriber::registry` + `fmt` 层 + `tracing_opentelemetry` 层；`OTEL_EXPORTER_OTLP_ENDPOINT` 非空时挂 `opentelemetry-otlp` 导出器，为空时用无导出器的 TracerProvider（trace id 仍由 SDK 生成）
- `crates/api`：
  - `middleware/trace.rs` 改写：`trace_id` 取当前 OTel span context（32 位十六进制），不再复用 `request_id`；`request_id` 保持既有语义（入站 `X-Request-Id` 或 UUID v7）
  - 新增 `middleware/propagation.rs`：解析入站 `traceparent`（W3C，`00-<32hex>-<16hex>-<2hex>`），合法则作为父上下文续接，非法/缺失则新建链路；响应头回写 `x-trace-id`（只回 trace id，不回完整 `traceparent`，避免误导调用方可以续接）
  - 新增 `guards.rs`：`apply_guards(router, &HttpConfig) -> Router`，按 06 §6.3.6 插入 `CORS → BodyLimit(2MB) → Timeout(30s)`
  - `router.rs`：中间件顺序改为 `RequestId → Trace(OTel) → Metrics → CORS → BodyLimit → Timeout → Audit → Handler`
- `docs/adr/008-observability.md`：§2 从"P0 过渡态"改为真 OTel 口径；§5 标记接入完成，补充导出器与采样说明
- `docs/tech-debt.md`：TD-001 偿还（SDK + bridge + 可选 OTLP 导出）、TD-002 偿还（trace_id 独立）、TD-004 部分偿还（BodyLimit/Timeout/CORS；Auth/RBAC/Idempotency 仍在 P2/P5）
- **不含**：collector 部署、OTLP 端到端后端检索（需用户提供 collector 地址）、Auth/RBAC/Idempotency/RateLimit、`traceparent` 出站注入（P5 有出站调用时再做）

## Impact

- Affected specs：P0-5（`trace_id` 语义从"等于 request_id"升级为 OTel trace）、P0-2（fmt/clippy/test 复跑）
- Affected code：`Cargo.toml`、`crates/shared/src/config.rs`、`crates/api/src/{router.rs,state.rs,middleware/*}`、`apps/server/src/{main.rs,telemetry.rs}`、`docs/`
- 契约影响：日志字段名不变（`trace_id` / `request_id` 同时存在，值不再相同）；响应新增 `x-trace-id`；新增 3 个可选环境变量
- 运维影响：新增 CORS 白名单配置；未配置 `CORS_ALLOWED_ORIGINS` 时浏览器跨域请求被拒（当前无前端，符合预期）
- `docs/spec/**` 与 `docs/prompt/MAIN.md` 只读，不修改

## 改动文件（白名单）

新增：

- `specs/ST-0.4.md`
- `apps/server/src/telemetry.rs`
- `crates/api/src/middleware/propagation.rs`
- `crates/api/src/guards.rs`

修改：

- `Cargo.toml`（workspace 依赖新增 `opentelemetry 0.27` / `opentelemetry_sdk 0.27` / `opentelemetry-otlp 0.27` / `tracing-opentelemetry 0.28` / `tower-http 0.6`）
- `crates/shared/src/config.rs`（`TelemetryConfig` / `HttpConfig` + 单测）
- `crates/api/Cargo.toml`、`crates/api/src/lib.rs`、`crates/api/src/state.rs`、`crates/api/src/router.rs`
- `crates/api/src/middleware/mod.rs`、`crates/api/src/middleware/trace.rs`
- `apps/server/Cargo.toml`、`apps/server/src/main.rs`
- `docs/adr/008-observability.md`
- `docs/tech-debt.md`（TD-001/TD-002 转已偿还，TD-004 更新范围）
- `docs/gates/P0.md`（ST-0.4 证据段落）

## 明确不改

- 不部署 collector，不依赖 docker；无 collector 时导出器不安装，服务照常启动
- 不引入 `tower-http` 的 `trace` 特性替换现有自研 trace / metrics 中间件（现有实现已带 `request_id` 与低基数标签）
- 不实现 Auth / RBAC / RateLimit / Idempotency / Compression
- 不改 `audit_log` 表结构与迁移；审计的 `trace_id` 自动变为真 trace id，无需迁移
- 不把 `traceparent` 回写给调用方作为续接依据（只回 `x-trace-id` 便于人工排查）

## ADDED Requirements

### Requirement: R1 遥测配置与装配

`AppConfig` SHALL 新增遥测配置；`apps/server` SHALL 在绑定端口前完成 subscriber 装配，且装配失败不得静默降级。

| 变量 | 必填 | 默认 | 校验 |
|---|---|---|---|
| `OTEL_SERVICE_NAME` | 否 | `ecom-server` | 非空、无空白 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | 否 | 空（不导出） | 为空或以 `http://` / `https://` 开头 |

#### Scenario: 无导出器也能启动
- **WHEN** 未设置 `OTEL_EXPORTER_OTLP_ENDPOINT`
- **THEN** 服务正常启动，日志 `telemetry` 段落打印 `otlp_export=false`，请求仍产生合法 32 位 `trace_id`

#### Scenario: 非法 endpoint 拒绝启动
- **WHEN** `OTEL_EXPORTER_OTLP_ENDPOINT=127.0.0.1:4317`（缺 scheme）
- **THEN** 启动退出码 2，问题清单指出该键，且凭据/地址按既有规则不回显敏感信息

### Requirement: R2 真 trace_id 与入站传播

每个请求 SHALL 携带一个 W3C trace 上下文；`trace_id` SHALL 为 32 位小写十六进制，`request_id` SHALL 保持独立。

- 入站 `traceparent` 合法（`00-<32hex>-<16hex>-<2hex>`）→ 沿用其 `trace_id` 作为本请求 trace
- 缺失或非法 → 由 SDK 新建 trace
- 响应头 SHALL 回写 `x-trace-id: <32hex>`
- 日志 `http_request` span SHALL 同时含 `trace_id` 与 `request_id`，两者不相等

#### Scenario: 调用方指定 trace
- **WHEN** 请求带 `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
- **THEN** 日志 `trace_id=4bf92f3577b34da6a3ce929d0e0e4736`，`request_id` 为 UUID v7，响应头 `x-trace-id` 同值

#### Scenario: 非法 traceparent 不被采信
- **WHEN** 请求带 `traceparent: 00-bad-...`（长度/字符非法）或 `ff-...`（非法版本）
- **THEN** 服务不报错，生成新 trace，且新 `trace_id` 不等于报文中的非法值

#### Scenario: 审计与日志同源
- **WHEN** 任一请求完成后查 `audit_log`
- **THEN** 最新行 `trace_id` 与同请求日志的 `trace_id` 一致（32 位十六进制）

### Requirement: R3 请求护栏中间件

`apply_guards` SHALL 按 06 §6.3.6 顺序安装 `CORS → BodyLimit → Timeout`，参数来自 `HttpConfig`。

- `BodyLimit`：请求体超过 `HTTP_BODY_LIMIT_BYTES` → `413 Payload Too Large`
- `Timeout`：处理超过 `HTTP_TIMEOUT_SECS` → `408 Request Timeout`
- `CORS`：仅对 `CORS_ALLOWED_ORIGINS` 中的来源回 `Access-Control-Allow-Origin`；未配置时不放行任何跨域来源
- 三层护栏 SHALL 排在 `Metrics` 之后、`Audit` 之前，保证被拒绝的请求仍被计数与审计

#### Scenario: 超大请求体
- **WHEN** `POST /healthz` 携带 3MB 请求体
- **THEN** 返回 413，且不进入 handler

#### Scenario: 超时
- **WHEN** 处理耗时超过配置的超时阈值（单测注入慢 handler）
- **THEN** 返回 408，`Metrics` 记录该状态码

#### Scenario: 跨域默认关闭
- **WHEN** 未配置 `CORS_ALLOWED_ORIGINS`，请求带 `Origin: https://evil.example`
- **THEN** 响应不含 `Access-Control-Allow-Origin`

### Requirement: R4 证据与台账

`docs/adr/008-observability.md` SHALL 更新为真 OTel 口径并记录导出器/采样策略；`docs/tech-debt.md` SHALL 将 TD-001、TD-002 置为已偿还并写偿还证据位置，TD-004 缩小为 Auth/RBAC/Idempotency/RateLimit；`docs/gates/P0.md` SHALL 追加本 ST 实测证据。

## 验证方式（A2 第 5 步，真实执行并原样粘贴）

1. `cargo fmt --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test --workspace`
4. 运行态（PG/Redis 已在 ST-0.3 就绪）：
   - `$env:JWT_SECRET=...; $env:DATABASE_URL=...; $env:REDIS_URL=...; cargo run -p server`
   - `curl.exe -s -i -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" http://127.0.0.1:8080/healthz` → 响应头含 `x-trace-id: 4bf92f35...`，日志 `trace_id` 同值且 `request_id` 为 UUID v7
   - `curl.exe -s -i -H "traceparent: 00-bad" http://127.0.0.1:8080/healthz` → 200，`x-trace-id` 为新生成值
   - `curl.exe -s -o NUL -w "%{http_code}" -X POST --data-binary @large.bin http://127.0.0.1:8080/healthz` → `413`
   - `psql ... -c "select trace_id, request_id, path, status from audit_log order by created_at desc limit 3"` → `trace_id` 为 32 位十六进制且与日志一致
5. `cargo tree -p domain --edges normal` 与 `cargo tree -p api --edges normal`（分层复验；`api` 不得出现 `sqlx` / `reqwest`）

## 新增依赖说明（C6）

| 依赖 | 位置 | 用途 | 是否在 06 §6.1 锁版 |
|---|---|---|---|
| `opentelemetry 0.27` | `apps/server`、`api` | trace 上下文与全局 tracer | 是 |
| `opentelemetry-otlp 0.27`（`grpc-tonic` + `trace`） | `apps/server` | OTLP 导出（endpoint 非空时才启用） | 是 |
| `opentelemetry_sdk 0.27`（`rt-tokio` / `trace`；dev 加 `testing`） | `apps/server` | TracerProvider、批量处理器、内存导出器（单测） | **否，需批准** |
| `tracing-opentelemetry 0.28` | `apps/server` | 把 `tracing` span 桥接为 OTel span（版本对应 `opentelemetry 0.27`，已核验） | **否，需批准** |
| `tower-http 0.6`（`cors` / `limit` / `timeout`） | `api` | 三层请求护栏 | 是 |

`opentelemetry_sdk` 是 `opentelemetry-otlp` 的必需配套（无它无法构造 `TracerProvider` 与 `BatchSpanProcessor`）；`tracing-opentelemetry` 是 `tracing` 与 OTel 之间唯一的官方桥接。二者虽未逐条列在 06 §6.1，但版本与锁版 `opentelemetry 0.27` 严格对应，无版本漂移。见"待确认 1"。

## 风险与回滚

- **风险（构建体积/时间）**：`opentelemetry-otlp` 默认 `grpc-tonic` 会引入 tonic / prost / hyper 栈，首次全量编译明显变长。缓解：仅 `apps/server` 依赖它；若不可接受，可改为 `http-proto`（见"待确认 2"）。
- **风险（trace 传播误判）**：若把非法 `traceparent` 当作合法父上下文，会污染后端检索。缓解：严格按 W3C 格式校验（48~55 字符、版本 `00`、全十六进制），非法一律新建；单测覆盖 4 类非法输入。
- **风险（CORS 默认关闭）**：P14 前端联调时若忘记配置会表现为"浏览器报跨域"，属预期行为，需在 `.env.example` 与部署文档中写明（本 ST 更新 `docs/gates/P0.md` §五）。
- **风险（Timeout 与审计顺序）**：Timeout 必须位于 Audit 之前，否则超时请求拿不到响应、审计中间件可能挂起。按 R3 固定顺序并在单测断言 408 被计数。
- **回滚**：删除 `apps/server/src/telemetry.rs`、`guards.rs`、`propagation.rs`，`main.rs` 恢复 `tracing_subscriber::fmt()` 直连、`trace.rs` 恢复 `trace_id = request_id`，移除 5 个 workspace 依赖。

## 待确认（已确认项）

1. **C6 报批**：`tracing-opentelemetry 0.28` 与 `opentelemetry_sdk 0.27` 引入——用户已确认"批准引入"。
2. **OTLP 传输方式**：用户已确认 `grpc-tonic`（4317）。
3. **本 ST 范围**：用户已确认"OTel + 三层护栏"（CORS / BodyLimit / Timeout 同轮落地）。
4. **CORS 默认策略**：用户已确认"默认全拒"，未配置 `CORS_ALLOWED_ORIGINS` 时不回任何跨域头。
5. **导出验证边界（默认采用）**：本机无 collector、无 docker，OTLP 端到端只做"代码就位 + `otlp_export=true` 日志"，真实后端检索留到具备 collector 时补证据；本 ST 不以 collector 证据作为完成条件。

## 范围外声明

本 ST 不产生业务能力，也不改变 P0 Gate 的达成项（P0-1~P0-5 维持 ✅）。它的价值是让 `trace_id` 从"能用"变成"可跨进程"，并给后续写接口预留请求体上限与超时这两道最低成本护栏。
