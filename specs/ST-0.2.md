# ST-0.2 配置加载与可观测基座 Spec

> 阶段：P0 工程基座｜本轮只做 ST-0.2，不写任何业务代码、不建表、不接 DB/Redis。
> 依据：`00-总纲与主Prompt.md`（A4 可观测锁定、C4/C6/C8）、`06-工程执行清单.md`（6.1 依赖锁版、6.2 文件级清单、6.3.6 中间件顺序、6.4 配置项）、`05-验收用例与Gate.md`（P0 Gate 第 4/5 条）。

## Why

ST-0.1 的进程能起来，但它是"盲"的：端口写死在常量、日志只有默认 `info` 文本、没有请求标识、没有指标。P0 Gate 第 4 条（`/metrics`）与第 5 条（`trace_id` 串联）完全没有承载物；后续每个 ST 的排障都会退化成"加 `println!` 再看"。

本 ST 只解决一件事：**让服务可配置、可关联、可度量**。配置在启动期一次性校验并 fail-fast，请求从入口拿到唯一标识并贯穿日志，指标按固定命名暴露给 Prometheus。

## What Changes

- 新增 `shared::config`：从环境变量装载 `AppConfig`（纯函数、可单测），**一次性收集全部问题**后返回 `ConfigError`（缺失 / 长度不足 / 非法值），由启动入口打印清单并以非零码退出（06 §6.4）
- `apps/server` 改为：先按 `APP_ENV`+`LOG_FORMAT`+`RUST_LOG` 装配 `tracing`（pretty / json 二选一），再装载并校验 `AppConfig`，失败打印缺失清单后退出；绑定地址来自配置而非常量
- 新增 `api::middleware::{request_id, trace, metrics}` 三层，按 06 §6.3.6 的相对顺序装配：`RequestId → Trace → Metrics → Handler`
- `request_id`：读取合法 `X-Request-Id`（`[A-Za-z0-9._-]{1,64}`）否则生成 UUID v7；写入请求扩展、响应头 `X-Request-Id`，并作为日志 span 的 `request_id` 字段
- `trace`：建立 `http_request` span，字段含 `method/path/request_id/trace_id/status/latency_ms`，请求结束打一条结构化事件（P0 Gate 第 5 条的"服务日志"环节）
- 新增 `GET /metrics`：`metrics-exporter-prometheus` 文本格式，暴露 `http_requests_total`（counter，标签 `method/path/status`）与 `http_request_duration_seconds`（histogram，标签 `method/path`），`path` 取 axum `MatchedPath`（低基数，C11 的同类要求）
- 新增 `docs/adr/008-observability.md`（ADR-001 预留给 ST-0.2）
- 新增 `docs/tech-debt.md`，登记本轮两处主动妥协（OTel SDK 导出推迟、`trace_id` 暂由 `request_id` 承担）
- **不含**：DB/Redis/`/readyz`、错误分层与完整中间件链（CORS/BodyLimit/Timeout/RateLimit/Auth/Idempotency）、OTLP 导出、采样策略、`crates/xtask`、业务路由

## Impact

- Affected specs：P0 Gate 第 4 条（本 ST 达成）、第 5 条（本 ST 达成"入口→服务日志"段，`DB 审计` 段仍归 ST-0.3）
- Affected code：`Cargo.toml`（workspace 依赖）、`crates/shared`、`crates/api`、`apps/server`、`docs/adr/`、`docs/tech-debt.md`、`docs/gates/P0.md`、`specs/`
- 契约影响：所有 HTTP 响应新增 `X-Request-Id` 头；新增 `/metrics` 端点；`api::router` 签名变为需要 `PrometheusHandle`
- `docs/spec/**` 与 `docs/prompt/MAIN.md` 只读，不修改

## 改动文件（白名单）

新增：

- `specs/ST-0.2.md`（内容与本 Spec 一致）
- `crates/shared/src/config.rs`（`AppConfig` / `LogConfig` / `JwtConfig` / `ConfigError` + 单测）
- `crates/api/src/middleware/mod.rs`（模块导出）
- `crates/api/src/middleware/request_id.rs`（请求标识 + 单测）
- `crates/api/src/middleware/trace.rs`（请求 span 与结束事件）
- `crates/api/src/middleware/metrics.rs`（recorder 安装、指标采集中间件、`/metrics` 渲染）
- `docs/adr/008-observability.md`
- `docs/tech-debt.md`

修改：

- `Cargo.toml`（workspace 依赖新增 `thiserror` / `uuid` / `metrics` / `metrics-exporter-prometheus`；`tracing-subscriber` 增加 `json` 特性）
- `crates/shared/Cargo.toml`（新增 `thiserror` 依赖）
- `crates/shared/src/lib.rs`（导出 `config`）
- `crates/api/Cargo.toml`（新增 `tracing` / `tower` / `uuid` / `metrics` / `metrics-exporter-prometheus`）
- `crates/api/src/lib.rs`（导出 `middleware`）
- `crates/api/src/router.rs`（改为接收 `PrometheusHandle`；挂 `/metrics`；补中间件；路由单测改为带 handle 构造）
- `apps/server/Cargo.toml`（新增 `shared` 依赖，见"待确认 3"）
- `apps/server/src/main.rs`（配置装载 + 日志装配 + 指标安装 + 绑定地址来自配置）
- `docs/adr/001-layering.md`（白名单表补 `apps/server → shared` 一行，见"待确认 3"）
- `docs/gates/P0.md`（追加 ST-0.2 证据，更新 P0-4/P0-5 状态）

## 明确不改

- 不引入 `sqlx` / `fred` / `reqwest` / `opentelemetry*`：DB、Redis、模型、OTLP 各自在对应 ST 引入并单独论证
- 不建 `migrations/`、不改 `/readyz` 行为（仍 404）、不写业务路由、不留 `todo!()` 占位
- 不实现完整中间件链：CORS / BodyLimit / Timeout / RateLimit / Auth / RBAC / Idempotency 顺延到 ST-0.4 及后续
- 不改 `shared` 既有语义，不把 env 读取塞进 `domain` / `application`（`AppConfig` 只依赖 `std` + `thiserror`）

## ADDED Requirements

### Requirement: R1 配置装载与启动期校验

`shared::config::AppConfig` SHALL 由环境变量（或等价键值集合）装载，并在一处集中校验；校验失败 SHALL 返回**聚合**了全部问题的 `ConfigError`，SHALL NOT 只报第一条；`apps/server` SHALL 打印完整问题清单并以非零退出码终止（06 §6.4）。

本轮强制项只有 `JWT_SECRET`（06 §6.4 明确要求启动校验长度）；`DATABASE_URL` / `REDIS_URL` / `S3_*` / `FIELD_ENCRYPT_KEY` / `PAY_*` / `AI_*` 在首次被代码消费的 ST 转为必填（本轮不读取，避免没法启动、P0-1 证据无从产生）。

| 变量 | 必填 | 默认 | 校验 |
|---|---|---|---|
| `APP_ENV` | 否 | `dev` | 枚举 `dev\|test\|prod` |
| `SERVER_BIND_ADDR` | 否 | `0.0.0.0:8080` | 可解析为 `SocketAddr` |
| `RUST_LOG` | 否 | `info,sqlx=warn` | 非空 |
| `LOG_FORMAT` | 否 | `prod` 下 `json`，其它 `pretty` | 枚举 `pretty\|json` |
| `JWT_SECRET` | **是** | — | 字节长度 ≥ 32 |
| `JWT_ACCESS_TTL_SEC` | 否 | `900` | > 0 且 < refresh |
| `JWT_REFRESH_TTL_SEC` | 否 | `1209600` | > access |

#### Scenario: 缺失即拒绝启动
- **WHEN** 未设置 `JWT_SECRET` 执行 `cargo run -p server`
- **THEN** 进程不绑定端口，日志打印问题清单（含 `JWT_SECRET` 与期望说明），退出码非 0

#### Scenario: 问题聚合
- **WHEN** 同时缺 `JWT_SECRET` 且 `SERVER_BIND_ADDR=not-an-addr`
- **THEN** 返回的 `ConfigError` 同时包含两条问题（单测断言），而非只报一条

#### Scenario: 密钥不泄漏
- **WHEN** 以 `{:?}` 打印 `AppConfig`
- **THEN** 输出中不出现 `JWT_SECRET` 的原文（`JwtConfig` 手写 `Debug` 打码，C28）

#### Scenario: 默认值生效
- **WHEN** 只设置长度 32 的 `JWT_SECRET`
- **THEN** `bind_addr == 0.0.0.0:8080`、`app_env == dev`、`log.format == pretty`、`log.filter == info,sqlx=warn`、`access_ttl == 900`、`refresh_ttl == 1209600`

### Requirement: R2 日志装配

`apps/server` SHALL 依据 `LogConfig` 装配 `tracing-subscriber`：`pretty` 用于本地、`json` 用于 `prod`；`EnvFilter` 取自 `RUST_LOG`；SHALL NOT 使用 `println!/eprintln!`（C4 与 workspace lint 已禁）。

#### Scenario: 格式可选
- **WHEN** `LOG_FORMAT=json` 启动并请求一次 `/healthz`
- **THEN** 每条日志为单行合法 JSON，且包含 `request_id` / `trace_id` 字段

### Requirement: R3 请求标识与 trace 串联

每个 HTTP 请求 SHALL 获得唯一标识：优先沿用合法入站 `X-Request-Id`（`[A-Za-z0-9._-]{1,64}`），否则生成 UUID v7；标识 SHALL 写入请求扩展、响应头 `X-Request-Id`，并作为 `http_request` span 的 `request_id` 与 `trace_id` 字段（P0 Gate 第 5 条）。

#### Scenario: 沿传入标识
- **WHEN** 请求 `/healthz` 且带 `X-Request-Id: p0-trace-001`
- **THEN** 响应头 `X-Request-Id` 为 `p0-trace-001`，完成日志中 `request_id=p0-trace-001 trace_id=p0-trace-001`

#### Scenario: 非法标识被替换
- **WHEN** 请求带 `X-Request-Id: a b c`（含空格/超长）
- **THEN** 响应头为新生成的 UUID v7，日志使用新值，入站值不进入日志（防日志注入）

#### Scenario: 无标识自动生成
- **WHEN** 请求不带 `X-Request-Id`
- **THEN** 响应头返回 36 字符 UUID v7（版本位为 7），单测断言

### Requirement: R4 指标暴露

`GET /metrics` SHALL 返回 Prometheus 文本格式，至少包含 `http_requests_total` 与 `http_request_duration_seconds`（P0 Gate 第 4 条）；标签 SHALL 限定为 `method` / `path` / `status`，`path` SHALL 取路由匹配模板（如 `/healthz`），SHALL NOT 使用原始 URI（防基数爆炸）。

#### Scenario: 指标可抓取
- **WHEN** 对已启动服务执行 `curl.exe -s http://127.0.0.1:8080/metrics`
- **THEN** 200，`Content-Type: text/plain; version=0.0.4`，正文含 `http_requests_total` 与 `http_request_duration_seconds_bucket`

#### Scenario: 请求被计数
- **WHEN** 先抓一次 `/metrics` 作为基线，再请求 `/healthz` 两次，再抓 `/metrics`
- **THEN** `http_requests_total{method="GET",path="/healthz",status="200"}` 至少增加 2

#### Scenario: 不自我放大
- **WHEN** 抓取 `/metrics` 本身
- **THEN** 该请求不计入 `path="/metrics"` 的计数（避免抓取频率污染业务指标）

### Requirement: R5 证据与决策落盘

`docs/gates/P0.md` SHALL 追加 ST-0.2 实测证据并把 P0-4 置 ✅、P0-5 置 🟡（DB 段归 ST-0.3）；`docs/adr/008-observability.md` SHALL 记录日志/指标/trace 口径；`docs/tech-debt.md` SHALL 记录本轮妥协及偿还条件（A1）。

#### Scenario: 证据可追溯
- **WHEN** 复查 P0-4
- **THEN** 能看到 `/metrics` 的真实响应片段与 fmt/clippy/test 输出

## 验证方式（A2 第 5 步，真实执行并原样粘贴）

1. `cargo fmt --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test --workspace`
4. `$env:JWT_SECRET='...32+...'; cargo run -p server` 后：
   - `curl.exe -i -H "X-Request-Id: p0-trace-001" http://127.0.0.1:8080/healthz`（看响应头与日志行）
   - `curl.exe -s http://127.0.0.1:8080/metrics`
   - 反向自证：去掉 `JWT_SECRET` 再启动，贴退出码与问题清单
5. `cargo tree -p domain --edges normal`（确认仍为空）

## 新增依赖说明（C6）

全部取自 06 §6.1 锁版清单，无清单外依赖：

| 依赖 | 位置 | 用途 | 活跃度 / 编译影响 | 替代方案为何不选 |
|---|---|---|---|---|
| `thiserror 2` | `shared` | 配置错误枚举 | 事实标准，体积小 | 手写 `Display/Error` 样板更多、易漏 |
| `uuid 1`（`v7`） | `api` | 生成时间有序请求标识 | 事实标准，编译开销小 | `nanoid`/自研计数器不在锁版清单，且 v7 可排序便于排障 |
| `metrics 0.24` + `metrics-exporter-prometheus 0.16` | `api` | 指标门面与 Prometheus 文本导出 | 约 +20~30 个传递依赖，编译时间中等 | `prometheus` crate 不在锁版清单；自研文本导出等于重写 exporter |
| `tower 0.5`（转正为普通依赖） | `api` | `ServiceBuilder` 固定中间件顺序 | 已在 workspace 依赖 | 手写嵌套 `layer` 顺序易错，且 06 §6.3.6 要求顺序可读 |
| `tracing`（普通依赖） | `api` | span 与结构化事件 | 已在 workspace 依赖 | 无（日志统一走 tracing） |

`tracing-subscriber` 仅增加 `json` 特性（06 §6.1 已列）。

## 风险与回滚

- 风险：`metrics-exporter-prometheus` 对 counter 自动追加 `_total`。若实测渲染名与 Gate 断言不一致，以实测为准调整指标名（不改 Gate）。验证命令会直接暴露。
- 风险：`uuid` v7 需 `v7` 特性；若 MSRV 冲突，退回 v4（同 crate，仅需改一行）。记录在 ADR-008。
- 风险：`/metrics` 无鉴权。P0 仅内网使用；部署侧（ST-0.5/ingress）限制来源，记入 `docs/tech-debt.md` 观察项。
- 回滚：删除本轮新增文件、还原 `router.rs`/`main.rs`/`Cargo.toml` 即可；无迁移、无数据影响。

## 待确认（不猜）

1. **OTel/OTLP 导出是否本轮做**：建议本轮只做 `tracing` + `request_id` + Prometheus，OTLP collector 与 SDK 导出推迟到 ST-0.3（compose 里才有 collector 可验证），并在 `tech-debt.md` 登记偿还条件。若要求本轮一次到位，需增加 `opentelemetry`/`opentelemetry-otlp` 依赖与无 collector 时的降级验证。
2. **`JWT_SECRET` 是否本轮强制必填**：按 06 §6.4 建议强制（证明"启动期拒绝"这一 Gate），代价是本地 `cargo run` 必须先设该环境变量。备选：`dev` 允许缺省并用固定占位值 + 启动 WARN，`prod` 强制。
3. **白名单扩展**：`apps/server → shared`（用于启动期配置类型）。ADR-001 §5 规定改白名单需先改 ADR 并书面确认；本轮会把该行补进 ADR-001 白名单表。备选：配置放 `apps/server/src/config.rs`，但 ST-0.3 起 `infrastructure` 也要读 DB 配置，届时仍需共享类型。

## 范围外声明

本轮不产生任何业务能力：没有订单、没有表、没有模型调用。`/metrics` 与 `X-Request-Id` 的价值在于让后续每个 ST 的"自证"有可观测载体。
