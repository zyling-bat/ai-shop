# ST-1.2 · 身份与权限域表（10 张）

- 阶段：P1 / ST-1.2（P1 第 2 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.1、§2.15、§2.16；05 §P1 Gate 1–2；ADR-002
- 前置：P0 全部完成；ST-1.1 已完成（`idempotency_record`、`outbox_event` 与约束断言落地）

## 1. 背景与目标

ST-1.1 只建了两张与业务域无关的通用表。P1 进入业务建模后，第一批必须有**身份与权限**，因为后续商家、商品、交易域的所有 `merchant_id / shop_id / user_id` 都指向这里，越权矩阵（P2 Gate）与后台权限模型也以此为根。

本 ST 只交付**表结构、约束、索引、可回滚迁移与约束断言**，不交付认证、鉴权、RBAC 中间件（归 P2）。

## 2. 范围

### 包含

1. 10 张表，一表一迁移（`up` / `down` 各一文件）：
   - `user`、`user_identity`、`user_profile`、`user_device`、`login_log`
   - `role`、`permission`、`role_permission`、`user_role`、`staff_account`
2. RBAC 基础种子 `scripts/seed_rbac.sql`：6 个系统角色、15 条权限、角色-权限映射，幂等（可重复执行，行数不变）
3. 扩展 `scripts/verify_p1_constraints.sql`：追加身份域的存在性、部分唯一索引、CHECK、`NULLS NOT DISTINCT` 与非法写入拒绝断言
4. 更新 `docs/gates/P1.md`：记录本批空库 up / 逐批 down / 再 up、断言与种子两次执行结果
5. 本 Spec 文件本身

### 不包含（明确不做）

- 不改任何 Rust 代码，不加依赖，不建 `crates/xtask`
- 不写登录、注册、Token 刷新、RBAC 鉴权、密码哈希、账号锁定（P2 交付；P2 Gate 的“5 次密码错误锁定”不由本 ST 证明）
- 不建商家 / 商品 / 交易 / 库存表；不建 `audit_log` 的业务审计扩展与月分区（见 §7 决策点）
- 不写 RBAC 之外的其他种子（地区字典、类目树、属性模板、测试商家/店铺、示例商品、测试账号、运力、税率、`feature_flag`），它们依赖尚未建的表
- 不写 `scripts/consistency_check.sql`（依赖订单/分账/结算表）
- 不改既有 `migrations/20261124143103_audit_log.*`、`20261125103000_*`、`20261125103100_*`
- 不改 `deploy/`、`Cargo.toml`、`Cargo.lock`

## 3. 字段定义

### 3.1 来源标注规则

02 §2.1 只对 `user`、`user_identity`、`staff_account` 给出字段级要点，其余表只给表名。因此本 Spec 用两列标注：

- **02 明示**：文档已写明的字段与约束，不得偏离
- **本 ST 提案**：按 §2.0 命名规范补齐的最小必要字段，**待用户确认后才落地**；后续 ST 只能追加列，不能改名改语义

所有表均具备 `id UUID PRIMARY KEY`、`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`deleted_at TIMESTAMPTZ NULL`（§2.0 通用列），`id` 由应用层生成 UUIDv7，DDL 不设默认值。

所有表**不建物理外键**（§2.0 第 3 条：跨域不建；本域内为保持各迁移可独立回滚，同样由应用层校验 + 巡检保证）。

### 3.2 `user`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `phone_hash` | `VARCHAR(64)` | **NOT NULL**；SHA-256 十六进制 | 02 明示（唯一，索引用哈希） |
| `phone_enc` | `TEXT` | NOT NULL；明文加密另存 | 02 明示（明文加密另存） |
| `email_hash` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `email_enc` | `TEXT` | NULL | 本 ST 提案 |
| `nickname` | `VARCHAR(64)` | NOT NULL DEFAULT `''` | 本 ST 提案 |
| `avatar` | `TEXT` | NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/frozen/cancelled` | 02 明示 |
| `realname_status` | `VARCHAR(32)` | NOT NULL DEFAULT `'unverified'`，CHECK ∈ `unverified/pending/verified/rejected` | 02 明示（取值本 ST 提案） |
| `level_id` | `UUID` | NULL | 02 明示 |
| `points_balance` | `BIGINT` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `last_login_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_user_phone_hash`：`UNIQUE (phone_hash) WHERE deleted_at IS NULL`
- `uq_user_email_hash`：`UNIQUE (email_hash) WHERE deleted_at IS NULL`
- `ix_user_status_created_at`：`(status, created_at DESC)`
- `ix_user_level_id`：`(level_id)`
- `ck_user_status`、`ck_user_realname_status`、`ck_user_points_balance`

按用户确认：`phone_hash` / `phone_enc` 必填，注册即绑手机，微信/Apple 首次登录必须走手机号绑定流程（P2 实现）。`email_hash` 仍可空，邮箱为可选绑定渠道；若后续要求邮箱也必填，另行确认后追加迁移。

**保留字警告**：`user` 是 PostgreSQL 保留字，建表、断言、种子与后续 sqlx 查询都必须写成 `"user"`；`role`、`permission` 等不是保留字，可直接使用。

### 3.3 `user_identity`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `channel` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `wechat/apple/phone/email` | 02 明示 |
| `external_id` | `VARCHAR(128)` | NOT NULL | 02 明示 |
| `union_id` | `VARCHAR(128)` | NULL | 02 明示 |
| `bound_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 02 明示 |

索引与约束：

- `uq_user_identity_channel_external_id`：`UNIQUE (channel, external_id) WHERE deleted_at IS NULL`（02 明示）
- `ix_user_identity_user_id`：`(user_id)`
- `ix_user_identity_union_id`：`(union_id) WHERE union_id IS NOT NULL AND deleted_at IS NULL`

### 3.4 `user_profile`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `gender` | `VARCHAR(8)` | NOT NULL DEFAULT `'unknown'`，CHECK ∈ `unknown/male/female` | 本 ST 提案 |
| `birthday` | `DATE` | NULL | 本 ST 提案 |
| `real_name_enc` | `TEXT` | NULL | 本 ST 提案 |
| `id_card_hash` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `id_card_enc` | `TEXT` | NULL | 本 ST 提案 |
| `province` / `city` / `district` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `bio` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `extra` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案 |
| `realname_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_user_profile_user_id`：`UNIQUE (user_id) WHERE deleted_at IS NULL`
- `ix_user_profile_id_card_hash`：`(id_card_hash) WHERE id_card_hash IS NOT NULL AND deleted_at IS NULL`
- `ck_user_profile_gender`

证件号不建唯一约束：02 未要求，且家庭成员/代办场景可能同证件；如需“一证一人”由 P2 实名流程确认后追加。

### 3.5 `user_device`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `device_id` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |
| `device_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'web'`，CHECK ∈ `web/h5/miniapp/app` | 本 ST 提案（与 02 §2.5 `channel` 取值对齐） |
| `os` / `os_version` / `app_version` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `push_token` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `last_active_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 本 ST 提案 |

索引与约束：

- `uq_user_device_user_id_device_id`：`UNIQUE (user_id, device_id) WHERE deleted_at IS NULL`
- `ix_user_device_device_id`：`(device_id)`
- `ck_user_device_type`

`push_token` 不建唯一：同一 token 可能被重装/换绑覆盖，唯一性由应用层在写入时维护（同时置空旧记录）。

### 3.6 `login_log`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NULL（账号不存在/校验失败时无主体） | 本 ST 提案 |
| `login_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `password/sms/oauth/refresh` | 本 ST 提案 |
| `channel` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `success` | `BOOLEAN` | NOT NULL | 本 ST 提案 |
| `fail_reason` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `ip` | `INET` | NULL | 本 ST 提案 |
| `user_agent` | `TEXT` | NULL | 本 ST 提案 |
| `device_id` | `VARCHAR(128)` | NULL | 本 ST 提案 |

索引：

- `ix_login_log_user_id_created_at`：`(user_id, created_at DESC)`
- `ix_login_log_ip_created_at`：`(ip, created_at DESC)`
- `ix_login_log_created_at`：`(created_at DESC)`

约定：本表**只增不改**，应用不执行 UPDATE/DELETE；`deleted_at` 仅为满足 §2.0 通用列，正常流程不写。02 §2.15 未将其列入月分区表，本 ST 不分区；日均量上升后再评估。

### 3.7 `role`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `code` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `scope` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `platform/merchant/shop` | 本 ST 提案 |
| `description` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `is_system` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_role_code`：`UNIQUE (code) WHERE deleted_at IS NULL`
- `ix_role_scope_status`：`(scope, status)`
- `ck_role_scope`、`ck_role_status`

### 3.8 `permission`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `code` | `VARCHAR(128)` | NOT NULL，形如 `order:read` | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `resource` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `action` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `description` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_permission_code`：`UNIQUE (code) WHERE deleted_at IS NULL`
- `ix_permission_resource_action`：`(resource, action)`

### 3.9 `role_permission`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `role_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `permission_id` | `UUID` | NOT NULL | 本 ST 提案 |

索引：

- `uq_role_permission_role_permission`：`UNIQUE (role_id, permission_id) WHERE deleted_at IS NULL`
- `ix_role_permission_permission_id`：`(permission_id)`

### 3.10 `user_role`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `role_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `scope_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `platform/merchant/shop` | 本 ST 提案 |
| `scope_id` | `UUID` | NULL（平台级为空） | 本 ST 提案 |
| `granted_by` | `UUID` | NULL | 本 ST 提案 |
| `granted_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 本 ST 提案 |

索引与约束：

- `uq_user_role_user_role_scope`：`UNIQUE (user_id, role_id, scope_type, scope_id) NULLS NOT DISTINCT WHERE deleted_at IS NULL`
- `ix_user_role_role_id`：`(role_id)`
- `ix_user_role_scope`：`(scope_type, scope_id)`
- `ck_user_role_scope_type`

使用 `NULLS NOT DISTINCT`（PG15+，本项目基线 PG17），否则 `scope_id IS NULL` 的平台级授权会因 NULL 互不相等而重复插入。此为本 ST 的显式技术选择，断言脚本会校验 `pg_index.indnullsnotdistinct = true`。

### 3.11 `staff_account`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NULL（平台员工为空） | 02 明示 |
| `shop_id` | `UUID` | NULL | 02 明示 |
| `dept` | `VARCHAR(64)` | NULL | 02 明示 |
| `employee_no` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `is_primary` | `BOOLEAN` | NOT NULL DEFAULT `false` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_staff_account_user_merchant_shop`：`UNIQUE (user_id, merchant_id, shop_id) NULLS NOT DISTINCT WHERE deleted_at IS NULL`
- `ix_staff_account_merchant_id`：`(merchant_id)`
- `ix_staff_account_shop_id`：`(shop_id)`
- `ck_staff_account_scope`：`CHECK (shop_id IS NULL OR merchant_id IS NOT NULL)`——店铺员工必须归属商家
- `ck_staff_account_status`

`merchant_id` / `shop_id` 指向商家域，本域不建物理外键（§2.0 第 3 条）。

## 4. 迁移与种子设计

### 4.1 迁移命名

沿用 ADR-002 的时间戳前缀体系，接在 `20261125103100` 之后，一文件一主题、一表一迁移：

| 序号 | 版本前缀 | 主题 |
|---|---|---|
| 1 | `20261125110000` | `user` |
| 2 | `20261125110100` | `user_identity` |
| 3 | `20261125110200` | `user_profile` |
| 4 | `20261125110300` | `user_device` |
| 5 | `20261125110400` | `login_log` |
| 6 | `20261125110500` | `role` |
| 7 | `20261125110600` | `permission` |
| 8 | `20261125110700` | `role_permission` |
| 9 | `20261125110800` | `user_role` |
| 10 | `20261125110900` | `staff_account` |

`down.sql` 只 `DROP TABLE IF EXISTS` 本表，保证可从最新版本逐条回滚到 `20261125103100` 而互不牵连。

### 4.2 RBAC 基础种子 `scripts/seed_rbac.sql`

不作为迁移（迁移只执行一次），而是可重复执行的独立脚本，符合 02 §2.16“种子脚本幂等”。

**角色（6 个，全部 `is_system = true`）**

| code | name | scope |
|---|---|---|
| `platform_admin` | 平台超级管理员 | platform |
| `platform_operator` | 平台运营 | platform |
| `merchant_admin` | 商家管理员 | merchant |
| `merchant_operator` | 商家运营 | merchant |
| `shop_admin` | 店铺管理员 | shop |
| `customer_service` | 客服 | merchant |

**权限（15 条）**

`user:read`、`user:manage`、`merchant:read`、`merchant:manage`、`shop:read`、`shop:manage`、`product:read`、`product:manage`、`order:read`、`order:manage`、`after_sale:read`、`after_sale:manage`、`settlement:read`、`settlement:manage`、`system:config`。`code` 由 `resource:action` 生成，`resource` / `action` 同步落列。

**角色-权限映射（41 条）**

| 角色 | 权限 |
|---|---|
| `platform_admin` | 全部 15 条 |
| `platform_operator` | 除 `user:manage`、`product:manage`、`order:manage`、`after_sale:manage`、`settlement:manage`、`system:config` 外的 9 条 |
| `merchant_admin` | `product:read/manage`、`order:read/manage`、`after_sale:read/manage`、`settlement:read` |
| `merchant_operator` | `product:read/manage`、`order:read`、`after_sale:read` |
| `shop_admin` | `product:read`、`order:read`、`after_sale:read` |
| `customer_service` | `order:read`、`after_sale:read/manage` |

实现要点：

- 主键用确定性 UUIDv7 形态：`('01930000-0000-7000-8000-' || lpad(to_hex(seq), 12, '0'))::uuid`，角色 seq 从 1、权限从 101、映射从 201 起，避免 `gen_random_uuid()` 破坏“UUIDv7 主键”约定
- 全部写入 `ON CONFLICT DO NOTHING`，两次执行行数不变
- 映射通过 `JOIN role ON code` + `JOIN permission ON code` 解析 `role_id` / `permission_id`，不硬编码 UUID
- 整个脚本单事务，失败即整体回滚

## 5. 验证

### 5.1 迁移可执行、可独立回滚（05 P1-1）

在新的空库 `ecom_p1_identity` 上执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 依次回滚 staff_account → user_role → ... → user
sqlx migrate run
```

断言：每次 `revert` 后仅目标表消失，其余表（含 ST-1.1 的 `idempotency_record`、`outbox_event` 与 `audit_log`）仍在；再次 `run` 后 13 张表全部恢复。

### 5.2 约束断言（05 P1-2 的身份域部分）

在既有 `scripts/verify_p1_constraints.sql` 追加第二段 `DO $$ ... $$`：

1. 10 张表存在
2. `uq_user_phone_hash`、`uq_user_email_hash`、`uq_user_identity_channel_external_id`、`uq_user_profile_user_id`、`uq_user_device_user_id_device_id`、`uq_role_code`、`uq_permission_code`、`uq_role_permission_role_permission` 均为唯一且带 `WHERE deleted_at IS NULL`
3. `uq_user_role_user_role_scope`、`uq_staff_account_user_merchant_shop` 为唯一、带软删条件且 `indnullsnotdistinct = true`
4. `user`、`role` 的状态 CHECK 与作用域 CHECK 存在，非法值写入被拒绝
5. `staff_account` 的 `shop_id` 有值而 `merchant_id` 为空时写入被拒绝
6. `user.points_balance` 负值写入被拒绝
7. 关键列存在：`user.phone_hash`、`user.points_balance`、`user_identity.channel`、`login_log.success`、`staff_account.is_primary`

非法写入均在子块内执行并回滚（`WHEN check_violation THEN NULL`），不污染数据；脚本整体只读，可重复执行。

### 5.3 种子幂等（05 P1-3 的 RBAC 部分）

```powershell
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_rbac.sql   # 第一次
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_rbac.sql   # 第二次
```

断言两次执行后：

- `role` = 6 行、`permission` = 15 行、`role_permission` = 41 行，无重复
- `md5(string_agg(code, ',' ORDER BY code))` 在 `role`、`permission` 两次执行间完全一致
- 无报错，退出码 0

其余字典种子（地区/类目/商品/测试账号等）依赖未建表，P1-3 只标记为部分完成。

### 5.4 本地开发库

对本地 `app` 库执行 `sqlx migrate run`，确认 10 条新迁移按序应用；再执行一次 `seed_rbac.sql` 得到基线权限数据。

### 5.5 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 退出码 0（本 ST 不改 Rust，用于证明无副作用）
- `git diff --check` 退出码 0；`git status --short` 全部落在白名单内

## 6. 文件白名单

新增：

- `specs/ST-1.2.md`
- `migrations/20261125110000_user.{up,down}.sql`
- `migrations/20261125110100_user_identity.{up,down}.sql`
- `migrations/20261125110200_user_profile.{up,down}.sql`
- `migrations/20261125110300_user_device.{up,down}.sql`
- `migrations/20261125110400_login_log.{up,down}.sql`
- `migrations/20261125110500_role.{up,down}.sql`
- `migrations/20261125110600_permission.{up,down}.sql`
- `migrations/20261125110700_role_permission.{up,down}.sql`
- `migrations/20261125110800_user_role.{up,down}.sql`
- `migrations/20261125110900_staff_account.{up,down}.sql`
- `scripts/seed_rbac.sql`

修改：

- `scripts/verify_p1_constraints.sql`（追加身份域断言段，保留 ST-1.1 段不变）
- `docs/gates/P1.md`（追加 ST-1.2 证据，更新 P1-1/P1-2/P1-3 进度）

明确不改：`apps/**`、`crates/**`、`Cargo.toml`、`Cargo.lock`、`deploy/**`、`docs/adr/**`、`docs/spec/**`、`docs/tech-debt.md`、`docs/gates/P0.md`、ST-1.1 的 4 个迁移、`migrations/20261124143103_audit_log.*`。

## 7. 已识别的决策点（不在本 ST 擅自决定）

1. **`audit_log` 业务审计列**：02 §2.1 要求 `actor_id/actor_type/action/target_type/target_id/before/after/ip/trace_id` 与按月分区。现有 `audit_log` 是 P0 请求审计（`trace_id/request_id/method/path/status/latency_ms`）。两者合并方式（加列 / 新建 `biz_audit_log`）牵涉 P0 既有写入路径与月分区改造，建议随 P2 审计模块一并决策，本 ST 不动。
2. **RBAC 种子口径**：按用户确认本 ST 先落地 6 角色 / 15 权限 / 41 映射的基线；这些 code 为**本 ST 提案**，P2 可追加新 code 或停用（`status='disabled'`），但不删除已有 code、不改其语义。若 P2 越权矩阵需要更细的权限点，走新增迁移与种子追加。
3. **手机号必填**：已确认 `phone_hash` / `phone_enc` NOT NULL；`email_hash` 保持可空。P2 注册流程必须保证“先微信/Apple 后绑手机”链路可用。
4. **`NULLS NOT DISTINCT`**：依赖 PG15+；本项目基线 PG17，`deploy/docker-compose.yml` 已是 PostgreSQL 17，可接受。

## 8. 完成定义

- 10 条迁移在空库 up 成功，可逐条 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误，ST-1.1 段仍通过
- `scripts/seed_rbac.sql` 连续执行两次，6/15/41 行不变、无报错、退出码 0
- `docs/gates/P1.md` 记录命令、退出码、断言与种子结论，以及 P1-1/P1-2/P1-3 进度变化
- 三条 Rust 门禁仍全绿，无白名单外改动
- 不声称认证、鉴权、RBAC 中间件、非 RBAC 种子、`audit_log` 扩展或任何后续域表已完成
