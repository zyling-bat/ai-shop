# ST-1.3 · 商家域表（12 张）

- 阶段：P1 / ST-1.3（P1 第 3 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.2、§2.13、§2.15、§2.16；05 §P1 Gate 1–3；ADR-002
- 前置：ST-1.1（幂等/outbox）、ST-1.2（身份与权限域 10 表）已完成并推送

## 1. 背景与目标

身份域建好后，第一个业务域是**商家**：商品（`spu/shop_id`）、交易（`order/merchant_id`）、结算（`settlement_order/merchant_id`）、保证金都挂在商家/店铺上。02 §2.2 已列出 12 张表，本 ST 把它们按 §2.0 通用列与命名规范落地为可回滚迁移、约束与断言。

本 ST 只交付**表结构、约束、索引、可回滚迁移、约束断言**（以及用户确认后的 demo 种子），不交付商家入驻流程、审核流、店铺装修编辑器、保证金扣款逻辑（归后续 P2/P4/P9）。

## 2. 范围

### 包含

1. 12 张表，一表一迁移（`up` / `down` 各一文件），编号接在 `20261125110900` 之后：
   `merchant`、`merchant_qualification`、`merchant_contract`、`shop`、`shop_decoration`、`shop_score`、`shop_category_auth`、`merchant_violation`、`merchant_appeal`、`deposit_account`、`deposit_record`、`merchant_bank_account`
2. 扩展 `scripts/verify_p1_constraints.sql`：追加商家域的存在性、部分唯一索引、CHECK、金额非负断言
3. 更新 `docs/gates/P1.md`：追加本批空库 up / 逐条 down / 再 up 与断言实测结果
4. 本 Spec 文件本身
5. `scripts/seed_merchant_demo.sql`：1 个测试商家 + 1 个店铺 + 1 个保证金账户，幂等

### 不包含（明确不做）

- 不改任何 Rust 代码，不加依赖，不建状态机枚举与单测（02 §2.13 的 12 套状态机不含 `merchant.status` / `shop.status`）
- 不写商家入驻、资质审核、合同签署、处罚/申诉处理、保证金扣款/充值、店铺装修发布等业务逻辑（P2/P4/P9）
- 不建商品/交易/结算/库存表；`shop_score` 只建表，不建日跑批与聚合任务
- 不建 `audit_log` 业务审计扩展与月分区（沿用 ST-1.2 的决策点，随 P2 审计模块决策）
- 不写 `scripts/consistency_check.sql`（依赖订单/分账/结算表）
- 不改既有 35 个迁移文件（`audit_log`、ST-1.1 4 个、ST-1.2 20 个）
- 不改 `deploy/`、`Cargo.toml`、`Cargo.lock`、`docs/spec/**`、`docs/prompt/MAIN.md`

## 3. 字段定义

### 3.1 来源标注规则

02 §2.2 只对 `merchant`、`shop`、`deposit_account`、`merchant_bank_account` 给出字段级要点，其余 8 张仅给表名。标注两列：

- **02 明示**：文档已写明的字段与约束，不得偏离
- **本 ST 提案**：按 §2.0 命名规范补齐的最小必要字段，**经用户确认后落地**；后续只能追加列，不能改名改语义

所有表均具备 `id UUID PRIMARY KEY`、`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`deleted_at TIMESTAMPTZ NULL`（§2.0 通用列），`id` 由应用层生成 UUIDv7，DDL 不设默认值。

所有表**不建物理外键**（§2.0 第 3 条）：`merchant_id` / `shop_id` 跨表引用由应用层校验 + 巡检保证，保证每张迁移可独立回滚。

金额一律 `NUMERIC(20,4)`；比率一律 `NUMERIC(10,6)`（`commission_rate`、`good_rate`、`rate`）。例外：02 §2.2 明示的 `shop.dsr_*` 与 `shop_score` 的 DSR 用 `NUMERIC(3,2)`（0–5 分制），以文档为准，不改写为 10,6。

### 3.2 `merchant`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `name` | `VARCHAR(128)` | NOT NULL | 本 ST 提案（主体名称，店铺名另存） |
| `type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `personal/company` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'applying'`，CHECK ∈ `applying/active/suspended/closed` | 02 明示 |
| `commission_rate` | `NUMERIC(10,6)` | NOT NULL DEFAULT `0`，CHECK `0 <= x <= 1` | 02 明示（默认类目费率） |
| `settle_cycle` | `VARCHAR(16)` | NOT NULL DEFAULT `'T+1'`，CHECK ∈ `T+1/T+7` | 02 明示 |
| `contact_name` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `contact_phone_hash` | `VARCHAR(64)` | NULL | 本 ST 提案（检索用 SHA-256） |
| `contact_phone_enc` | `TEXT` | NULL | 本 ST 提案（敏感字段加密） |
| `email_hash` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `email_enc` | `TEXT` | NULL | 本 ST 提案 |
| `province` / `city` / `district` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `address` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `applied_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `activated_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `suspended_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `closed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `extra` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案 |

索引与约束：

- `uq_merchant_merchant_no`：`UNIQUE (merchant_no) WHERE deleted_at IS NULL`
- `ix_merchant_status_created_at`：`(status, created_at DESC)`
- `ix_merchant_type_status`：`(type, status)`
- `ck_merchant_type`、`ck_merchant_status`、`ck_merchant_settle_cycle`、`ck_merchant_commission_rate`

### 3.3 `merchant_qualification`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `qual_type` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `business_license/legal_id/brand_auth/special_license/other` | 本 ST 提案 |
| `qual_no` | `VARCHAR(128)` | NULL | 本 ST 提案（证件编号明文，敏感时由应用层只写 hash） |
| `qual_no_hash` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `file_url` | `TEXT` | NOT NULL | 本 ST 提案 |
| `valid_from` / `valid_to` | `DATE` | NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'pending'`，CHECK ∈ `pending/approved/rejected/expired` | 本 ST 提案 |
| `submitted_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 本 ST 提案 |
| `reviewed_by` | `UUID` | NULL | 本 ST 提案 |
| `reviewed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `reject_reason` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_merchant_qualification_merchant_type`：`UNIQUE (merchant_id, qual_type) WHERE deleted_at IS NULL AND qual_type IN ('business_license', 'legal_id')`——营业执照与法人身份证各一份，品牌授权可多条
- `ix_merchant_qualification_merchant_id`：`(merchant_id, qual_type)`
- `ix_merchant_qualification_status`：`(status, submitted_at DESC)`
- `ck_merchant_qualification_type`、`ck_merchant_qualification_status`

### 3.4 `merchant_contract`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `contract_no` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `contract_type` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `platform_service/settlement/supplement/other` | 本 ST 提案 |
| `start_at` / `end_at` | `DATE` | `start_at` NOT NULL，`end_at` NULL | 本 ST 提案 |
| `signed_at` | `DATE` | NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/pending_sign/active/expired/terminated` | 本 ST 提案 |
| `commission_rate` | `NUMERIC(10,6)` | NULL，CHECK `0 <= x <= 1` | 本 ST 提案（合同费率快照） |
| `settle_cycle` | `VARCHAR(16)` | NULL，CHECK ∈ `T+1/T+7` | 本 ST 提案 |
| `file_url` | `TEXT` | NULL | 本 ST 提案 |
| `remark` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_merchant_contract_contract_no`：`UNIQUE (contract_no) WHERE deleted_at IS NULL`
- `ix_merchant_contract_merchant_id`：`(merchant_id, status)`
- `ix_merchant_contract_end_at`：`(end_at) WHERE end_at IS NOT NULL AND deleted_at IS NULL`
- `ck_merchant_contract_type`、`ck_merchant_contract_status`、`ck_merchant_contract_settle_cycle`、`ck_merchant_contract_commission_rate`、`ck_merchant_contract_period`（`end_at IS NULL OR end_at >= start_at`）

### 3.5 `shop`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 02 明示 |
| `shop_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `name` | `VARCHAR(128)` | NOT NULL | 02 明示 |
| `logo` | `TEXT` | NULL | 02 明示 |
| `intro` | `VARCHAR(500)` | NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/applying/active/suspended/closed` | 02 明示字段，取值本 ST 提案 |
| `dsr_desc` / `dsr_service` / `dsr_logistics` | `NUMERIC(3,2)` | NOT NULL DEFAULT `5.00`，CHECK `0 <= x <= 5` | 02 明示（精度 3,2） |
| `main_category_id` | `UUID` | NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `opened_at` / `closed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `extra` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案 |

索引与约束：

- `uq_shop_shop_no`：`UNIQUE (shop_no) WHERE deleted_at IS NULL`
- `ix_shop_merchant_id`：`(merchant_id, status)`
- `ix_shop_status_created_at`：`(status, created_at DESC)`
- `ix_shop_main_category_id`：`(main_category_id)`
- `ck_shop_status`、`ck_shop_dsr_desc`、`ck_shop_dsr_service`、`ck_shop_dsr_logistics`

### 3.6 `shop_decoration`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `shop_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `page` | `VARCHAR(32)` | NOT NULL DEFAULT `'home'`，CHECK ∈ `home/category/custom` | 本 ST 提案 |
| `version` | `INTEGER` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 本 ST 提案 |
| `layout` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案（组件化布局快照，不可变） |
| `theme` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案 |
| `is_published` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `published_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_shop_decoration_shop_page_version`：`UNIQUE (shop_id, page, version) WHERE deleted_at IS NULL`
- `uq_shop_decoration_published`：`UNIQUE (shop_id, page) WHERE deleted_at IS NULL AND is_published`——每个页面同时只有一个已发布版本
- `ix_shop_decoration_shop_id`：`(shop_id, page)`
- `ck_shop_decoration_page`、`ck_shop_decoration_version`

### 3.7 `shop_score`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `shop_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `stat_date` | `DATE` | NOT NULL | 本 ST 提案 |
| `dsr_desc` / `dsr_service` / `dsr_logistics` | `NUMERIC(3,2)` | NOT NULL DEFAULT `0`，CHECK `0 <= x <= 5` | 本 ST 提案（与 `shop.dsr_*` 同精度） |
| `review_count` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `good_rate` | `NUMERIC(10,6)` | NOT NULL DEFAULT `0`，CHECK `0 <= x <= 1` | 本 ST 提案 |

索引与约束：

- `uq_shop_score_shop_date`：`UNIQUE (shop_id, stat_date) WHERE deleted_at IS NULL`
- `ix_shop_score_stat_date`：`(stat_date)`
- `ck_shop_score_dsr_desc`、`ck_shop_score_dsr_service`、`ck_shop_score_dsr_logistics`、`ck_shop_score_review_count`、`ck_shop_score_good_rate`

### 3.8 `shop_category_auth`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `shop_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `category_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'pending'`，CHECK ∈ `pending/approved/rejected/expired/revoked` | 本 ST 提案 |
| `source` | `VARCHAR(32)` | NOT NULL DEFAULT `'apply'`，CHECK ∈ `apply/platform_grant` | 本 ST 提案 |
| `rate` | `NUMERIC(10,6)` | NULL，CHECK `0 <= x <= 1` | 本 ST 提案（该店铺该类目费率覆盖） |
| `valid_from` / `valid_to` | `DATE` | NULL | 本 ST 提案 |
| `reviewed_by` | `UUID` | NULL | 本 ST 提案 |
| `reviewed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `reject_reason` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_shop_category_auth_shop_category`：`UNIQUE (shop_id, category_id) WHERE deleted_at IS NULL`
- `ix_shop_category_auth_category_id`：`(category_id, status)`
- `ix_shop_category_auth_valid_to`：`(valid_to) WHERE valid_to IS NOT NULL AND deleted_at IS NULL`
- `ck_shop_category_auth_status`、`ck_shop_category_auth_source`、`ck_shop_category_auth_rate`、`ck_shop_category_auth_period`（`valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from`）

### 3.9 `merchant_violation`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `shop_id` | `UUID` | NULL | 本 ST 提案 |
| `violation_type` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `product/fake/price/service/logistics/fraud/other` | 本 ST 提案 |
| `level` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `warning/minor/major/severe` | 本 ST 提案 |
| `title` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |
| `detail` | `TEXT` | NULL | 本 ST 提案 |
| `evidence` | `JSONB` | NOT NULL DEFAULT `'[]'::jsonb` | 本 ST 提案（证据 URL 列表） |
| `penalty_type` | `VARCHAR(32)` | NOT NULL DEFAULT `'none'`，CHECK ∈ `none/warning/points_deduct/suspend/close/confiscate` | 本 ST 提案 |
| `penalty_amount` | `NUMERIC(20,4)` | NULL，CHECK `>= 0` | 本 ST 提案 |
| `points_deduct` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'effective'`，CHECK ∈ `effective/revoked/appealed` | 本 ST 提案 |
| `effective_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 本 ST 提案 |
| `operator_id` | `UUID` | NULL | 本 ST 提案 |

索引与约束：

- `ix_merchant_violation_merchant_id`：`(merchant_id, created_at DESC)`
- `ix_merchant_violation_shop_id`：`(shop_id, created_at DESC)`
- `ix_merchant_violation_status`：`(status, effective_at DESC)`
- `ck_merchant_violation_type`、`ck_merchant_violation_level`、`ck_merchant_violation_penalty_type`、`ck_merchant_violation_penalty_amount`、`ck_merchant_violation_points_deduct`、`ck_merchant_violation_status`

### 3.10 `merchant_appeal`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `appeal_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `violation_id` | `UUID` | NULL | 本 ST 提案（针对处罚单；其他类型为空） |
| `appeal_type` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `violation/qualification/settlement/other` | 本 ST 提案 |
| `reason` | `TEXT` | NOT NULL | 本 ST 提案 |
| `evidence` | `JSONB` | NOT NULL DEFAULT `'[]'::jsonb` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'submitted'`，CHECK ∈ `submitted/reviewing/approved/rejected/closed` | 本 ST 提案 |
| `result` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `handled_by` | `UUID` | NULL | 本 ST 提案 |
| `handled_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_merchant_appeal_appeal_no`：`UNIQUE (appeal_no) WHERE deleted_at IS NULL`
- `ix_merchant_appeal_merchant_id`：`(merchant_id, status)`
- `ix_merchant_appeal_violation_id`：`(violation_id)`
- `ck_merchant_appeal_type`、`ck_merchant_appeal_status`、`ck_merchant_appeal_violation`（`appeal_type <> 'violation' OR violation_id IS NOT NULL`）

### 3.11 `deposit_account`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 02 明示（唯一） |
| `balance_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `frozen_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `currency` | `CHAR(3)` | NOT NULL DEFAULT `'CNY'` | 本 ST 提案（§2.0 币种约定） |
| `last_txn_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_deposit_account_merchant_id`：`UNIQUE (merchant_id) WHERE deleted_at IS NULL`
- `ck_deposit_account_balance_amount`、`ck_deposit_account_frozen_amount`、`ck_deposit_account_frozen_le_balance`（`frozen_amount <= balance_amount`）

### 3.12 `deposit_record`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `account_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `record_no` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `direction` | `VARCHAR(8)` | NOT NULL，CHECK ∈ `in/out` | 本 ST 提案 |
| `amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `balance_after` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 本 ST 提案 |
| `biz_type` | `VARCHAR(32)` | NOT NULL，CHECK ∈ `recharge/deduct/refund/freeze/unfreeze/adjust` | 本 ST 提案 |
| `biz_ref` | `VARCHAR(64)` | NULL | 本 ST 提案（外部业务单号） |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'success'`，CHECK ∈ `pending/success/failed` | 本 ST 提案 |
| `occurred_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | 本 ST 提案 |
| `remark` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_deposit_record_record_no`：`UNIQUE (record_no) WHERE deleted_at IS NULL`
- `ix_deposit_record_merchant_id`：`(merchant_id, occurred_at DESC)`
- `ix_deposit_record_account_id`：`(account_id, occurred_at DESC)`
- `ck_deposit_record_direction`、`ck_deposit_record_amount`、`ck_deposit_record_balance_after`、`ck_deposit_record_biz_type`、`ck_deposit_record_status`

约定：本表**只增不改**，应用不执行 UPDATE/DELETE（冲正走新的 `adjust` 记录）；`deleted_at` 仅为满足 §2.0 通用列。

### 3.13 `merchant_bank_account`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `account_no_enc` | `TEXT` | NOT NULL | 02 明示（敏感字段加密） |
| `account_no_hash` | `VARCHAR(64)` | NOT NULL | 本 ST 提案（去重与检索，SHA-256） |
| `account_no_last4` | `CHAR(4)` | NOT NULL | 本 ST 提案（展示用后四位） |
| `bank_name` | `VARCHAR(128)` | NOT NULL | 02 明示 |
| `bank_branch` | `VARCHAR(128)` | NULL | 本 ST 提案 |
| `holder` | `VARCHAR(64)` | NOT NULL | 02 明示 |
| `is_default` | `BOOLEAN` | NOT NULL DEFAULT `false` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |
| `verified_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_merchant_bank_account_no`：`UNIQUE (account_no_hash) WHERE deleted_at IS NULL`——同一张卡不重复绑定
- `uq_merchant_bank_account_default`：`UNIQUE (merchant_id) WHERE deleted_at IS NULL AND is_default`——每个商家只有一个默认账户
- `ix_merchant_bank_account_merchant_id`：`(merchant_id, status)`
- `ck_merchant_bank_account_status`

## 4. 迁移与种子设计

### 4.1 迁移命名

沿用 ADR-002 时间戳前缀，接在 `20261125110900` 之后，一表一迁移：

| 序号 | 版本前缀 | 主题 |
|---|---|---|
| 1 | `20261125111000` | `merchant` |
| 2 | `20261125111100` | `merchant_qualification` |
| 3 | `20261125111200` | `merchant_contract` |
| 4 | `20261125111300` | `shop` |
| 5 | `20261125111400` | `shop_decoration` |
| 6 | `20261125111500` | `shop_score` |
| 7 | `20261125111600` | `shop_category_auth` |
| 8 | `20261125111700` | `merchant_violation` |
| 9 | `20261125111800` | `merchant_appeal` |
| 10 | `20261125111900` | `deposit_account` |
| 11 | `20261125112000` | `deposit_record` |
| 12 | `20261125112100` | `merchant_bank_account` |

`down.sql` 只 `DROP TABLE IF EXISTS` 本表，保证可从最新版本逐条回滚到 `20261125110900` 而互不牵连。

### 4.2 demo 种子（已确认落地）

`scripts/seed_merchant_demo.sql`，非迁移、可重复执行：

- 1 个测试商家：`merchant_no = 'M_DEMO_0001'`，`type='company'`，`status='active'`，`commission_rate=0.050000`，`settle_cycle='T+1'`
- 1 个店铺：`shop_no = 'S_DEMO_0001'`，挂在该商家下，`status='active'`
- 1 个保证金账户：`merchant_id` 指向该商家，`balance_amount=10000.0000`
- 主键用确定性 UUID（`01930000-0000-7000-8000-` 前缀 + 序号），全部 `ON CONFLICT DO NOTHING`
- 单事务，失败整体回滚

不含违规/申诉/合同/资质/装修/评分/银行卡示例数据，避免与后续业务规则的演示数据冲突。

## 5. 验证

### 5.1 迁移可执行、可独立回滚（05 P1-1）

在空库 `ecom_p1_merchant` 上执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 依次回滚 merchant_bank_account → deposit_record → ... → merchant
sqlx migrate run
```

断言：每次 `revert` 后仅目标表消失；ST-1.1 / ST-1.2 的 13 张表始终存在；再次 `run` 后 25 张表全部恢复。

### 5.2 约束断言（05 P1-2 的商家域部分）

在 `scripts/verify_p1_constraints.sql` 追加第三段 `DO $$ ... $$`：

1. 12 张表存在
2. 部分唯一索引存在且唯一、带 `WHERE deleted_at IS NULL`：`uq_merchant_merchant_no`、`uq_merchant_contract_contract_no`、`uq_shop_shop_no`、`uq_shop_decoration_shop_page_version`、`uq_shop_score_shop_date`、`uq_shop_category_auth_shop_category`、`uq_merchant_appeal_appeal_no`、`uq_deposit_account_merchant_id`、`uq_deposit_record_record_no`、`uq_merchant_bank_account_no`
3. 条件唯一索引额外带业务过滤条件：`uq_merchant_qualification_merchant_type`（含 `qual_type IN (...)`）、`uq_shop_decoration_published`（含 `is_published`）、`uq_merchant_bank_account_default`（含 `is_default`）
4. CHECK 约束全部存在（各表状态/类型/金额/区间）
5. 非法写入被拒绝（子块回滚，无残留）：
   - `merchant.status='bogus'`、`merchant.commission_rate=1.5`
   - `shop.dsr_desc=6`、`shop.status='bogus'`
   - `deposit_account.balance_amount=-1`、`frozen_amount > balance_amount`
   - `deposit_record.amount=0`
   - `shop_decoration` 同 `(shop_id, page)` 插入两条 `is_published=true`
   - `merchant_bank_account` 同商家插入第二个 `is_default=true`
   - `merchant_qualification` 同商家插入第二条 `business_license`

### 5.3 种子幂等（05 P1-3 的商家域部分，若确认种子）

```powershell
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_merchant_demo.sql   # 第一次
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_merchant_demo.sql   # 第二次
```

断言：`merchant` / `shop` / `deposit_account` 各 1 行，两次执行行数与 `merchant_no` 哈希一致，无报错。

### 5.4 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 退出码 0（本 ST 不改 Rust）
- `git diff --check` 退出码 0；`git status --short` 全部落在白名单内

## 6. 文件白名单

新增：

- `specs/ST-1.3.md`
- `migrations/20261125111000_merchant.{up,down}.sql`
- `migrations/20261125111100_merchant_qualification.{up,down}.sql`
- `migrations/20261125111200_merchant_contract.{up,down}.sql`
- `migrations/20261125111300_shop.{up,down}.sql`
- `migrations/20261125111400_shop_decoration.{up,down}.sql`
- `migrations/20261125111500_shop_score.{up,down}.sql`
- `migrations/20261125111600_shop_category_auth.{up,down}.sql`
- `migrations/20261125111700_merchant_violation.{up,down}.sql`
- `migrations/20261125111800_merchant_appeal.{up,down}.sql`
- `migrations/20261125111900_deposit_account.{up,down}.sql`
- `migrations/20261125112000_deposit_record.{up,down}.sql`
- `migrations/20261125112100_merchant_bank_account.{up,down}.sql`
- `scripts/seed_merchant_demo.sql`

修改：

- `scripts/verify_p1_constraints.sql`（追加商家域断言段，保留 ST-1.1/ST-1.2 段不变）
- `docs/gates/P1.md`（追加 ST-1.3 证据，更新 P1-1/P1-2/P1-3 进度）

明确不改：`apps/**`、`crates/**`、`Cargo.toml`、`Cargo.lock`、`deploy/**`、`docs/adr/**`、`docs/spec/**`、`docs/prompt/MAIN.md`、`docs/tech-debt.md`、`docs/gates/P0.md`、既有 35 个迁移。

## 7. 已确认的决策点

用户已确认：12 张表一次交付、含 demo 种子、不产出 `merchant.status` / `shop.status` 的 Rust 状态机与单测。

1. **批次范围**：12 张表一次交付（本 Spec 默认），或拆成「主体 6 张（merchant 系 + shop）」与「运营 6 张（装修/评分/类目授权/违规/申诉/银行卡）」。存款 2 张可随商家域或推迟到 P9 结算域。
2. **demo 种子**：是否本批落地测试商家 + 店铺 + 保证金账户（用于 P1-3 与后续开发联调）。
3. **状态机**：`merchant.status` / `shop.status` 不在 02 §2.13 的 12 套状态机内，本 ST 默认**不**产出 Rust 状态机与单测；若要求纳入，属于超出 02 契约的新增，需要单独确认并在 ADR/02 更新后再做。
4. **敏感字段**：`merchant.contact_phone_enc`、`merchant_bank_account.account_no_enc`、`qual_no` 的加密密钥与算法归 P2，本 ST 只约定「密文列 + 哈希列 + 明文展示尾部」，不实现加解密。

## 8. 完成定义

- 12 条迁移在空库 up 成功，可逐条 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误，ST-1.1 / ST-1.2 段仍通过
- （若确认）`scripts/seed_merchant_demo.sql` 连续两次执行行数不变、无报错
- `docs/gates/P1.md` 记录命令、退出码与断言结论，并更新 P1-1/P1-2/P1-3 进度
- 三条 Rust 门禁仍全绿，无白名单外改动
- 不声称商家入驻/审核/处罚/申诉/保证金业务逻辑、店铺装修编辑器或任何后续域表已完成
