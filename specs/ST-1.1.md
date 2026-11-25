# ST-1.1 · 基础契约表：幂等记录与 outbox

- 阶段：P1 / ST-1.1（P1 第 1 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.14、§2.16；05 §P1 Gate 1–2；06 §6.3.5；ADR-002；ADR-004
- 前置：P0 全部完成（`docs/gates/P0.md` 六项 ✅）

## 1. 背景与目标

P1 的第一件事不是铺业务表，而是先把**所有业务写入都会依赖的两张通用表**按契约建好：

- `idempotency_record`（C14：所有写接口的幂等基础）
- `outbox_event`（C18 / ADR-004：跨服务副作用的唯一出口）

这两张表的字段在 02 §2.14 已定稿，且不依赖任何业务域外键，可以在身份/商品/交易表之前独立落地。本 ST 同时把 §2.0 的通用列与索引命名规则落到真实迁移上，为后续每批迁移提供可复制样板。

本 ST **不实现**其读写代码（幂等中间件归 P4/P5，outbox worker 归 P5）；只交付表、约束、可回滚迁移与约束断言。

## 2. 范围

### 包含

1. 迁移 A：`idempotency_record`
2. 迁移 B：`outbox_event`
3. 约束断言脚本：对上述两表的存在性、唯一索引、CHECK、部分索引条件做可重复执行的 SQL 断言
4. 新增 `docs/gates/P1.md`，记录本批的空库 up/down 与断言实测输出
5. 本 Spec 文件本身

### 不包含（明确不做）

- 不改任何 Rust 代码、不加依赖、不建 `crates/xtask`
- 不写幂等中间件、不写 outbox 投递/消费者、不写定时任务
- 不建身份、商品、交易等业务表
- 不写种子数据（本批无字典类数据；`feature_flag` 全量默认值随系统表批次单独交付）
- 不写 `scripts/consistency_check.sql`（其三条断言依赖订单/分账/结算表，必须等对应批次建表后成文，避免空壳）
- 不改 `audit_log` 既有迁移，不改 `deploy/`、`Cargo.toml`

## 3. 迁移设计与命名

### 3.1 命名

02 §2.16 要求“顺序编号、一文件一主题”。ADR-002 已确定用 `sqlx migrate add -r` 生成，版本号是单调时间戳前缀，语义等价于顺序编号；沿用既有 `20261124143103_audit_log` 的形态，不另起 `0001_` 体系（避免两套编号并存）。

本批文件名：

- `migrations/20261125103000_idempotency_record.up.sql`
- `migrations/20261125103000_idempotency_record.down.sql`
- `migrations/20261125103100_outbox_event.up.sql`
- `migrations/20261125103100_outbox_event.down.sql`

一个文件只建一张表；`down.sql` 只 `DROP TABLE` 该表，保证可独立回滚。

### 3.2 `idempotency_record`

字段按 02 §2.14 原样落地：

| 列 | 类型 | 约束 |
|---|---|---|
| `id` | `UUID` | PK |
| `scope` | `VARCHAR(64)` | NOT NULL |
| `key` | `VARCHAR(128)` | NOT NULL |
| `request_hash` | `CHAR(64)` | NOT NULL |
| `status` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `processing/done/failed` |
| `response` | `JSONB` | NULL |
| `expires_at` | `TIMESTAMPTZ` | NOT NULL |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` |
| `deleted_at` | `TIMESTAMPTZ` | NULL |

索引与约束：

- `uq_idempotency_record_scope_key`：`UNIQUE (scope, key) WHERE deleted_at IS NULL`（02 §2.0 要求软删表用部分唯一索引）
- `ix_idempotency_record_expires_at`：`(expires_at)`，供过期清理扫描
- CHECK 命名 `ck_idempotency_record_status`

`processing` 超过 60s 视为可重试属应用层判定，本 ST 不建相关任务。

### 3.3 `outbox_event`

字段按 02 §2.14 原样落地：

| 列 | 类型 | 约束 |
|---|---|---|
| `id` | `UUID` | PK（行主键） |
| `event_id` | `UUID` | NOT NULL，唯一（业务事件标识，冲突时 `DO NOTHING` 的依据） |
| `aggregate_type` | `VARCHAR(64)` | NOT NULL |
| `aggregate_id` | `VARCHAR(64)` | NOT NULL |
| `event_type` | `VARCHAR(128)` | NOT NULL |
| `payload` | `JSONB` | NOT NULL |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'pending'`，CHECK ∈ `pending/sent/failed/dead` |
| `retry_count` | `SMALLINT` | NOT NULL DEFAULT `0`，CHECK `>= 0` |
| `next_retry_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` |
| `sent_at` | `TIMESTAMPTZ` | NULL |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` |
| `deleted_at` | `TIMESTAMPTZ` | NULL |

索引与约束：

- `uq_outbox_event_event_id`：`UNIQUE (event_id) WHERE deleted_at IS NULL`
- `ix_outbox_event_status_next_retry_at`：`(status, next_retry_at)`，投递扫描主索引
- CHECK 命名 `ck_outbox_event_status`、`ck_outbox_event_retry_count`

`failed` 与 `dead` 的语义以 ADR-004 为准；本 ST 只保证状态值受 CHECK 约束。

### 3.4 通用列与跨域外键

- 两表均具备 `id/created_at/updated_at/deleted_at`（02 §2.0）
- 不建任何物理外键：`aggregate_id` 是弱引用，由应用层保证（02 §2.0 第 3 条）
- 金额列不涉及，无 `NUMERIC(20,4)` 使用

## 4. 验证

### 4.1 迁移可执行、可独立回滚（对应 05 P1-1）

在空库执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 回滚 outbox_event
sqlx migrate revert   # 回滚 idempotency_record
sqlx migrate run
```

断言：每次 `revert` 后 `to_regclass('public.<table>')` 为空，且另一张表仍在；再次 `run` 后两张表均恢复。

### 4.2 关键约束断言（对应 05 P1-2 中幂等表条目）

新增 `scripts/verify_p1_constraints.sql`，用 `DO $$ ... $$` + `pg_indexes` / `pg_constraint` 查询断言下列事实，任一不符即 `RAISE EXCEPTION`：

1. `idempotency_record`、`outbox_event` 存在
2. `uq_idempotency_record_scope_key` 存在且为唯一索引、定义包含 `WHERE (deleted_at IS NULL)`
3. `uq_outbox_event_event_id` 存在且唯一
4. `ix_outbox_event_status_next_retry_at` 存在，列为 `(status, next_retry_at)`
5. 两条 CHECK 存在，且拒绝非法状态值（插入验证需在事务内 `ROLLBACK`，不影响数据）

执行方式：`psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/verify_p1_constraints.sql`

重复执行两次结果一致（脚本只读断言，不写数据）。

### 4.3 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 仍退出码 0（本 ST 不改 Rust 代码，用于证明无副作用）
- `git diff --check` 退出码 0

## 5. 文件白名单

新增：

- `specs/ST-1.1.md`
- `migrations/20261125103000_idempotency_record.up.sql`
- `migrations/20261125103000_idempotency_record.down.sql`
- `migrations/20261125103100_outbox_event.up.sql`
- `migrations/20261125103100_outbox_event.down.sql`
- `scripts/verify_p1_constraints.sql`
- `docs/gates/P1.md`

明确不改：`apps/**`、`crates/**`、`Cargo.toml`、`Cargo.lock`、`deploy/**`、`docs/adr/**`、`docs/spec/**`、既有 `migrations/20261124143103_audit_log.*`、`docs/gates/P0.md`、`docs/tech-debt.md`。

## 6. 遗留与风险

- 本机无 Docker（P0 已记录），迁移执行沿用本机原生 PostgreSQL；不声称 compose 实测。
- CI 目前只跑 fmt/clippy/test，不跑数据库迁移；P1-1/P1-2 靠本地实测 + Gate 记录，迁移的自动 CI 校验随 TD-006（`.sqlx/`）与后续数据库 CI 一并偿还。
- `idempotency_record.status` 与 `outbox_event.status` 是状态列但不是 02 §2.13 的 12 套业务状态机，因此本 ST 不产出 Rust 状态机与迁移矩阵测试；对应状态机单测归各业务域 ST。
- 02 §2.16 的种子要求（地区字典、类目、feature_flag 默认值等）在本批无承载表，整体推迟到对应表落地批次，不做空种子占位。

## 7. 完成定义

- 两条迁移在空库 up 成功，可逐个 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误
- `docs/gates/P1.md` 记录命令、退出码与断言结论
- 三条 Rust 门禁仍全绿，无白名单外改动
- 不声称幂等中间件、outbox 投递或任何业务表已完成
