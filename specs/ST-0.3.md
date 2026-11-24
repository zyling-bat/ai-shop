# ST-0.3 数据库 / 缓存基座与就绪探针 Spec

> 阶段：P0 工程基座｜本轮只做 ST-0.3：接入 PostgreSQL 17 + Redis 7、可回滚迁移、`/readyz`、审计落库与 ADR-002/003。
> 依据：`06-工程执行清单.md`（6.1 依赖锁版、6.3.5 outbox 语义、6.4 配置项、6.5 改动边界）、`05-验收用例与Gate.md`（§5.1 P0-1/P0-3/P0-5）、`00-总纲与主Prompt.md`（C3/C6/C9/C10/C13/C18/C30）、`docs/adr/001-layering.md` §5。

## Why

ST-0.2 之后服务"可配置、可关联、可度量"，但仍不接触任何持久化：`/readyz` 是 404，P0-1 的 DB+Redis 检查没有承载物；P0-3 没有迁移可跑；P0-5 的"DB 审计"一段缺失。后续所有 ST 都要读配置、连库、查缓存，这层不先立起来，后面每个 ST 都要临时造轮子。

本 ST 只解决一件事：**让"依赖可用性"与"请求留痕"变成可验证的工程能力**——启动期 fail-fast 建池、`/readyz` 分别报告 PostgreSQL 与 Redis、首个可回滚迁移、审计行带 `trace_id` 落库。

## What Changes

- `shared::config` 新增 `DATABASE_URL`（必填，`postgres://`/`postgresql://`）、`DATABASE_MAX_CONNECTIONS`（默认 20）、`REDIS_URL`（必填，`redis://`/`rediss://`），错误信息与 `Debug` 均对 URL 密码脱敏
- `crates/application` 新增端口：`HealthProbe` / `ProbeReport` / `Readiness`（就绪检查编排）与 `AuditSink` / `AuditEntry`（审计写入端口）
- `crates/infrastructure` 新增：
  - `db`：`sqlx::PgPool` 连接池（`max_connections` 来自配置，`acquire_timeout` 5s）、`PgProbe`（`SELECT 1`，2s 超时）
  - `redis`：`deadpool-redis` 连接池、`RedisProbe`（`PING`，2s 超时）
  - `audit`：`PgAuditSink` 写入 `audit_log`
  - `bootstrap`：一次装配连接池、探针与审计端口，供 `apps/server` 使用
- `crates/api`：`AppState { metrics, readiness, audit }`；新增 `GET /readyz`（全 up → 200，任一 down/无探针 → 503，JSON 含每个探针的 `name/status/latency_ms`）；新增审计中间件（请求结束后写一行审计，失败只记日志与计数，不影响响应）
- `apps/server`：启动期建池并注入；DB/Redis 连接失败以退出码 3 终止；优雅退出时关闭 DB 池
- `migrations/` 首个可回滚迁移：`audit_log` 表（C10：主键 + `created_at/updated_at/deleted_at`）
- `deploy/docker-compose.yml`：`postgres:17` + `redis:7`（静态交付；本机无 docker，不作为本 ST 验证依据）
- 新增 `docs/adr/002-database.md`、`docs/adr/003-cache-lock.md`；`docs/tech-debt.md` 按 06 §6.8 改为表格
- **不含**：OTel/OTLP（TD-001 偿还条件改为 ST-0.4）、业务表、业务路由、outbox 实现、分布式锁实现、编译期查询校验接线（见 TD-006）

## Impact

- Affected specs：P0-1（本 ST 达成代码与探针，实测依赖运行环境）、P0-3（迁移文件就绪，实测依赖 PG）、P0-5（本 ST 补 DB 审计段）、P0-6（ADR-002/003 落地）
- Affected code：`Cargo.toml`、`crates/{shared,application,infrastructure,api}`、`apps/server`、`migrations/`、`deploy/`、`docs/`
- 契约影响：新增 `GET /readyz`；`api::router` 入参由 `PrometheusHandle` 改为 `AppState`；启动必填项新增 `DATABASE_URL`、`REDIS_URL`
- `docs/spec/**` 与 `docs/prompt/MAIN.md` 只读，不修改

## 改动文件（白名单）

新增：

- `specs/ST-0.3.md`
- `crates/application/src/health.rs`
- `crates/application/src/audit.rs`
- `crates/infrastructure/src/db.rs`
- `crates/infrastructure/src/redis.rs`
- `crates/infrastructure/src/audit.rs`
- `crates/infrastructure/src/bootstrap.rs`
- `crates/api/src/state.rs`
- `crates/api/src/middleware/audit.rs`
- `crates/api/src/handlers/readyz.rs`
- `migrations/<timestamp>_audit_log.up.sql` / `.down.sql`
- `deploy/docker-compose.yml`
- `docs/adr/002-database.md`
- `docs/adr/003-cache-lock.md`

修改：

- `Cargo.toml`（workspace 依赖新增 `serde` / `serde_json` / `sqlx 0.8` / `deadpool-redis 0.23` / `async-trait`）
- `crates/shared/src/config.rs`（DB/Redis 配置 + 脱敏 + 单测）
- `crates/application/Cargo.toml`、`crates/application/src/lib.rs`
- `crates/infrastructure/Cargo.toml`、`crates/infrastructure/src/lib.rs`
- `crates/api/Cargo.toml`、`crates/api/src/lib.rs`、`crates/api/src/router.rs`、`crates/api/src/middleware/mod.rs`、`crates/api/src/middleware/metrics.rs`（审计失败计数描述）
- `apps/server/Cargo.toml`、`apps/server/src/main.rs`
- `docs/adr/001-layering.md`（白名单新增 `apps/server → infrastructure`，见"待确认 1"）
- `docs/tech-debt.md`（表格化 + TD-005/TD-006，TD-001 偿还条件改 ST-0.4）
- `docs/gates/P0.md`（ST-0.3 证据与状态）

## 明确不改

- 不写任何业务表/业务路由；`audit_log` 是基础设施审计表，不含业务字段
- 不实现 outbox、分布式锁、限流、认证；不接 OTLP
- 不在启动时自动跑迁移（迁移由 `sqlx migrate run` 显式执行，避免生产误变更）
- 不引入锁版清单之外的新依赖；`sqlx` 仅启用 `runtime-tokio-rustls/postgres/uuid`

## ADDED Requirements

### Requirement: R1 依赖配置与启动期校验

`AppConfig` SHALL 新增数据库与 Redis 配置并保持"一次收集全部问题"；URL 密码 SHALL NOT 出现在错误信息、`Debug` 或日志中（C28）。

| 变量 | 必填 | 默认 | 校验 |
|---|---|---|---|
| `DATABASE_URL` | **是** | — | `postgres://` 或 `postgresql://` 开头、无空白、主体非空 |
| `DATABASE_MAX_CONNECTIONS` | 否 | `20` | 正整数 |
| `REDIS_URL` | **是** | — | `redis://` 或 `rediss://` 开头、无空白、主体非空 |

#### Scenario: 缺失即拒绝启动
- **WHEN** 未设置 `DATABASE_URL` 或 `REDIS_URL`
- **THEN** 启动退出码 2，问题清单逐条列出缺失项

#### Scenario: 密码脱敏
- **WHEN** `DATABASE_URL=postgres://app:s3cret@127.0.0.1:5432/app` 且格式非法
- **THEN** 错误信息与 `{:?}` 输出中的密码为 `***`，不出现 `s3cret`

### Requirement: R2 依赖连接与就绪探针

`apps/server` SHALL 在绑定端口前创建 PostgreSQL 与 Redis 连接池；任一依赖不可用 SHALL 以退出码 3 终止并打印原因。`GET /readyz` SHALL 逐项报告探针：

- 全部 `up` 且至少一个探针 → `200`
- 任一 `down` 或无探针 → `503`
- 响应体 SHALL 为 JSON：`{ "status": "ready|not_ready", "probes": [{ "name", "status", "latency_ms", "error"? }] }`
- 探针 SHALL 各自带超时（2s），超时视为 `down`

#### Scenario: 依赖正常
- **WHEN** PostgreSQL 与 Redis 可用时请求 `/readyz`
- **THEN** 200，`probes` 含 `postgres` 与 `redis` 且均为 `up`

#### Scenario: Redis 不可用
- **WHEN** Redis 停止后请求 `/readyz`
- **THEN** 503，`redis` 为 `down` 且含简短原因（不含连接串）

#### Scenario: 无探针不伪装成功
- **WHEN** 以空探针集合构造 `AppState`
- **THEN** `/readyz` 返回 503（单测断言）

### Requirement: R3 可回滚迁移

首个迁移 SHALL 为 `up/down` 成对文件，`sqlx migrate run` 在空库成功，`sqlx migrate revert` 能回到空库；`audit_log` SHALL 含 `id` 主键与 `created_at/updated_at/deleted_at`（C10），时间列 SHALL 为 `TIMESTAMPTZ`（C9）。

#### Scenario: 空库往返
- **WHEN** 对空库执行 `sqlx migrate run` 再 `sqlx migrate revert`
- **THEN** 两次成功，第二次后 `audit_log` 不存在

### Requirement: R4 请求审计落库（P0-5 DB 段）

每个 HTTP 请求（`/metrics` 除外）SHALL 在响应完成后写一行 `audit_log`，字段含 `trace_id`/`request_id`/`method`/`path`/`status`/`latency_ms`；写入失败 SHALL NOT 改变响应状态，但 SHALL 记 WARN 日志并累加 `audit_write_failures_total`。

#### Scenario: trace 串联
- **WHEN** 带 `X-Request-Id: p0-trace-001` 请求 `/healthz`
- **THEN** 日志 `trace_id=p0-trace-001`，且 `SELECT trace_id FROM audit_log ORDER BY created_at DESC LIMIT 1` 返回 `p0-trace-001`

#### Scenario: 审计故障降级
- **WHEN** 审计端口返回错误
- **THEN** 响应仍为原状态码，日志出现 `审计写入失败`，指标计数增加

### Requirement: R5 证据与决策落盘

`docs/gates/P0.md` SHALL 追加本 ST 实测证据并更新 P0-1/P0-3/P0-5；ADR-002/003 SHALL 记录选型与语义；`docs/tech-debt.md` SHALL 按 06 §6.8 表格化，新增探针审计噪声（TD-005）与编译期查询校验（TD-006）。

## 验证方式（A2 第 5 步，真实执行并原样粘贴）

1. `cargo fmt --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test --workspace`
4. 依赖可用时（需要用户提供 `DATABASE_URL` / `REDIS_URL`）：
   - `sqlx migrate run` / `sqlx migrate revert`（空库往返）
   - `$env:JWT_SECRET=...; $env:DATABASE_URL=...; $env:REDIS_URL=...; cargo run -p server`
   - `curl.exe -s -i -H "X-Request-Id: p0-trace-001" http://127.0.0.1:8080/readyz`
   - `psql "$env:DATABASE_URL" -c "select trace_id, path, status from audit_log order by created_at desc limit 3"`
   - 停 Redis 后再请求 `/readyz`，贴 503 证据
5. `cargo tree -p domain --edges normal` 与 `cargo tree -p api --edges normal`（确认分层）

## 新增依赖说明（C6）

| 依赖 | 位置 | 用途 | 理由 / 替代方案 |
|---|---|---|---|
| `sqlx 0.8`（`runtime-tokio-rustls`,`postgres`,`uuid`） | `infrastructure` | PG 连接池、探针、审计写入 | A4 锁定版本；`tokio-postgres` 不在锁版清单且缺少池化与迁移生态 |
| `deadpool-redis 0.23` | `infrastructure` | Redis 连接池与 PING 探针 | 用户在 ST-0.3 决策中选择 deadpool-redis（替代 fred）；API 简单、池化开箱可用 |
| `async-trait 0.1` | `application` | 端口 trait 异步方法 | 06 §6.1 锁版；Rust 2024 原生 async trait 在 trait object 场景仍不便 |
| `serde 1` / `serde_json 1` | `api` | `/readyz` JSON 响应 | 06 §6.1 锁版；axum `Json` 依赖 |
| `tracing` / `tokio` / `uuid` / `thiserror` | `infrastructure` | 日志、超时、审计主键、错误 | 已在 workspace 依赖 |

`sqlx` 本轮只用运行时查询（`query_scalar`/`query`），未接编译期校验与 `.sqlx` 离线元数据（P0 无业务查询），登记 TD-006。

## 风险与回滚

- 风险：`sqlx` 连接错误文本可能含主机信息但不含密码；错误只进日志，不回显给 HTTP 调用方。
- 风险：审计与业务同库同步写入会增加一次 INSERT 延迟（P0 流量可忽略）；后续按 TD-005 收敛。
- 风险：本机无 PostgreSQL/Redis 时 `/readyz` 与迁移证据无法产生；启动会 fail-fast（退出码 3），不会伪装健康。
- 回滚：删除本 ST 新增文件与 `migrations/`，还原 `router.rs`/`main.rs`/`Cargo.toml`；`sqlx migrate revert` 可撤销表结构。

## 待确认（已确认项）

1. **`apps/server → infrastructure` 依赖边**：用户已书面确认"批准"，ADR-001 变更记录同步登记。
2. **P0-5 DB 审计是否本 ST 落地**：用户已确认"本 ST 落地"。
3. **运行环境**：用户选择"本地原生服务"，连接串待提供；本轮不假设 docker 可用。

## 范围外声明

本 ST 不产生业务能力：没有订单、商品、支付。`/readyz`、迁移与审计的价值是让后续每个 ST 的依赖可用性与请求留痕可自证。
