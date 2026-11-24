# ADR-002 数据库访问与迁移策略

- 状态：已接受（Accepted）
- 日期：2026-11-24
- 阶段：P0 / ST-0.3
- 关联约束：A4（PostgreSQL 17 + sqlx 0.8）、C3（分层）、C6（新依赖报批）、C8（金额 `NUMERIC(20,4)`）、C9（时间 `TIMESTAMPTZ`）、C10（迁移只追加）、C28（日志不落敏感信息）、06 §6.3.5 / §6.4、05 §5.1 P0-1 / P0-3 / P0-5

## 背景

ST-0.3 起服务必须连接 PostgreSQL：`/readyz` 要检查 DB，首个迁移要跑通且可回滚，审计行要带 `trace_id` 落库。需要一次定清楚：客户端与版本、连接池参数、迁移的命名/执行/回滚方式、查询校验时机，以及启动期是否自动迁移。

## 决策

### 1. 客户端与版本

- 使用 `sqlx 0.8`（`default-features = false`，特性 `runtime-tokio-rustls` / `postgres` / `uuid`），与 A4 锁定版本一致。
- 不引入 `diesel` / `sea-orm`：两者会带来独立 schema DSL 或代码生成流程，和 C10"迁移只追加"以及后续 outbox/状态机的显式 SQL 风格不一致；`tokio-postgres` 缺少池化与迁移生态。
- 目标库为 PostgreSQL 17；本机原生安装或 `deploy/docker-compose.yml` 二选一，连接串由 `DATABASE_URL` 提供。

### 2. 连接池参数

| 项 | 值 | 依据 |
|---|---|---|
| `max_connections` | `DATABASE_MAX_CONNECTIONS`，默认 20 | 06 §6.4 |
| `acquire_timeout` | 5s | 启动期尽早暴露池耗尽；常量 `infrastructure::db::ACQUIRE_TIMEOUT` |
| 探活超时 | 2s | `/readyz` 必须在探针超时前返回；常量 `infrastructure::db::PROBE_TIMEOUT` |
| 探活语句 | `SELECT 1` | 只验证连接可用，不读业务表 |

连接池在 `infrastructure::bootstrap` 中创建；`apps/server` 在绑定端口**之前**完成装配，失败以退出码 3 终止（fail-fast，不提供"降级为不健康但继续服务"的假象）。

### 3. 迁移

- 目录：仓库根 `migrations/`；文件由 `sqlx migrate add -r <name>` 生成，命名 `{timestamp}_{name}.up.sql` / `.down.sql`。
- 只追加，不修改已发布的迁移文件（C10）。
- 每个迁移必须提供 `.down.sql`；`sqlx migrate revert` 必须能回到上一版本。
- **不在启动时自动迁移**：迁移由部署流程显式执行（本机 `sqlx migrate run`），避免多实例启动竞争与"代码已起、schema 未评审"的不可控变更。
- 本轮首个迁移 `20261124143103_audit_log` 只建 `audit_log`，含主键与 `created_at` / `updated_at` / `deleted_at`（C10），时间列 `TIMESTAMPTZ`（C9）。

### 4. 查询校验时机

- P0 只有 `SELECT 1`、审计 `INSERT` 两类查询，使用运行时 `sqlx::query` / `query_scalar`，不引入 `DATABASE_URL` 编译期依赖，保证 `cargo test` 在无数据库的机器上可运行。
- 业务查询（P1 起）必须使用 `sqlx::query!` / `query_as!` 编译期校验，并把 `.sqlx/` 离线元数据入库供 CI 使用（A4）。P0 未接这一层，登记为 TD-006，偿还条件为首个业务查询 ST。

### 5. 审计写入

- `audit_log` 由 API 中间件在**响应生成后**同步写入：不改变响应状态，失败只记 WARN 与 `audit_write_failures_total`。
- 同步等待而非 `spawn`：P0 请求量极低，先保证"请求返回时审计已落库"的可验证性；异步化/批量写入随 outbox 在 P5 评估。
- 探针请求（`/healthz`、`/readyz`）也会留痕，生产流量下的噪声与采样策略登记为 TD-005。

### 6. 日志与错误文本

连接失败只输出 `PostgreSQL 连接失败` 与本层错误链；`DatabaseConfig` 的 `Debug` 对 URL 密码脱敏（`***`），配置校验错误同样脱敏。HTTP 响应不返回任何驱动错误文本。

## 后果

- 正面：启动即验证依赖、`/readyz` 可逐项定位故障、迁移可回滚、审计可自证 trace 串联；`cargo test` 不依赖数据库。
- 负面：业务查询尚未获得编译期校验（TD-006）；审计同步写带来一次 INSERT 延迟（P0 可接受，TD-005 收敛）。
- 回滚：删除 `migrations/*_audit_log.*` 并 `sqlx migrate revert`；还原 `infrastructure` 的 `db`/`audit`/`bootstrap` 与 `apps/server` 装配。
