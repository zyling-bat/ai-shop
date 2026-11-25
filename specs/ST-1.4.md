# ST-1.4 · 商品域表（18 张）

- 阶段：P1 / ST-1.4（P1 第 4 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.3、§2.13⑦、§2.15、§2.16；05 §P1 Gate 1–3；ADR-002
- 前置：ST-1.1、ST-1.2、ST-1.3 已完成并推送（`8d114d2`）

## 1. 背景与目标

商家域建好后，商品是交易的前置：`order_item.sku_id`、`sku_price` 的价格引擎（P5）、`sku_stock`（P1 下一批）都依赖 `spu/sku`。02 §2.3 列出 18 张表，本 ST 按 §2.0 落成可回滚迁移、约束与断言。

本 ST 只交付**表结构、约束、索引、可回滚迁移、约束断言**（以及用户确认后的字典/示例种子），不交付商品发布、审核流转、价格计算、运费试算、标签运营等业务逻辑。

## 2. 范围

### 包含

1. 18 张表，一表一迁移（`up` / `down` 各一文件），编号接在 `20261125112100` 之后：
   `category`、`category_attr`、`category_attr_value`、`brand`、`spu`、`spu_attr_value`、`sku`、`sku_spec`、`sku_media`、`sku_price`、`product_media`、`product_detail`、`product_audit`、`freight_template`、`freight_template_rule`、`product_tag`、`product_limit`、`product_qa`
2. 扩展 `scripts/verify_p1_constraints.sql`：追加商品域的存在性、部分唯一索引、CHECK、金额/数量非负断言
3. 更新 `docs/gates/P1.md`：追加本批空库 up / 逐条 down / 再 up 与断言实测结果
4. 本 Spec 文件本身
5. `scripts/seed_product_dict.sql`：类目树 + 品牌 + 类目属性模板 + 20 个示例商品

### 不包含（明确不做）

- 不改任何 Rust 代码；不写商品审核状态机（⑦）的 enum/单测（待确认，见 §7）
- 不写商品发布、上下架、审核流转、SKU 生成、价格计算、运费试算、标签运营、问答审核等业务逻辑
- 不建库存（`warehouse/sku_stock/stock_log` 等）、交易、营销、内容、AI 表
- 不建 `region_dict`；`sku_price.region_code` 与运费规则地区用字符串弱引用
- 不建 `audit_log` 业务审计扩展与月分区（沿用 ST-1.2 决策点）
- 不写 `scripts/consistency_check.sql`
- 不改既有 59 个迁移文件与 `docs/spec/**`、`docs/prompt/MAIN.md`

## 3. 字段定义

### 3.1 来源标注规则

02 §2.3 只对 `spu`、`sku`、`sku_price`、`product_audit`、`product_limit`、`product_qa` 给出字段级要点，其余 12 张仅给表名。标注两列：

- **02 明示**：文档已写明的字段与约束，不得偏离
- **本 ST 提案**：按 §2.0 命名规范补齐的最小必要字段，**经用户确认后落地**；后续只能追加列，不能改名改语义

所有表均具备 `id UUID PRIMARY KEY`、`created_at`、`updated_at`、`deleted_at`（§2.0 通用列），`id` 由应用层生成 UUIDv7，DDL 不设默认值。

所有表**不建物理外键**（§2.0 第 3 条）：`spu_id` / `sku_id` / `category_id` 等跨表引用由应用层校验 + 巡检保证，保证每张迁移可独立回滚。

金额 `NUMERIC(20,4)`；比率 `NUMERIC(10,6)`；数量 `INTEGER` 或 `NUMERIC(20,4)`（重量/体积用后者）。`machine_score` 用 `NUMERIC(5,2)`（0–100 分制，与 02 的 DSR 同属非比率分数）。

### 3.2 `category`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `parent_id` | `UUID` | NULL（一级类目为空） | 本 ST 提案 |
| `code` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `level` | `SMALLINT` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 本 ST 提案 |
| `path` | `TEXT` | NOT NULL DEFAULT `'/'`（形如 `/a/b/c/`，便于子树查询） | 本 ST 提案 |
| `icon` | `TEXT` | NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `is_leaf` | `BOOLEAN` | NOT NULL DEFAULT `true` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_category_code`：`UNIQUE (code) WHERE deleted_at IS NULL`
- `ix_category_parent_id`：`(parent_id, sort_weight)`
- `ix_category_status_level`：`(status, level)`
- `ck_category_level`、`ck_category_status`

### 3.3 `category_attr`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `category_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `code` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `attr_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'sale'`，CHECK ∈ `sale/key/prop` | 本 ST 提案 |
| `input_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'text'`，CHECK ∈ `text/number/select/multi_select/bool` | 本 ST 提案 |
| `is_required` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `is_sku_attr` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `is_searchable` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `is_filterable` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `unit` | `VARCHAR(16)` | NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_category_attr_category_code`：`UNIQUE (category_id, code) WHERE deleted_at IS NULL`
- `ix_category_attr_category_id`：`(category_id, sort_weight)`
- `ck_category_attr_type`、`ck_category_attr_input_type`、`ck_category_attr_status`

### 3.4 `category_attr_value`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `attr_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `value` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_category_attr_value_attr_value`：`UNIQUE (attr_id, value) WHERE deleted_at IS NULL`
- `ix_category_attr_value_attr_id`：`(attr_id, sort_weight)`
- `ck_category_attr_value_status`

### 3.5 `brand`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `name_en` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `first_letter` | `CHAR(1)` | NULL | 本 ST 提案 |
| `logo` | `TEXT` | NULL | 本 ST 提案 |
| `description` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_brand_name`：`UNIQUE (name) WHERE deleted_at IS NULL`
- `ix_brand_first_letter`：`(first_letter, sort_weight)`
- `ck_brand_status`

### 3.6 `spu`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `merchant_id` | `UUID` | NOT NULL | 02 明示 |
| `shop_id` | `UUID` | NOT NULL | 02 明示 |
| `category_id` | `UUID` | NOT NULL | 02 明示 |
| `brand_id` | `UUID` | NULL | 02 明示 |
| `title` | `VARCHAR(255)` | NOT NULL | 02 明示 |
| `sub_title` | `VARCHAR(255)` | NULL | 02 明示 |
| `main_image` | `TEXT` | NULL | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/pending/on_sale/off_sale/banned` | 02 明示字段，取值本 ST 提案 |
| `audit_status` | `VARCHAR(32)` | NOT NULL DEFAULT `'none'`，CHECK ∈ `none/pending/machine_reviewing/human_reviewing/approved/rejected/need_supplement` | 02 明示字段，取值与 §2.13⑦ 对齐（`none` 为未提交） |
| `is_self_support` | `BOOLEAN` | NOT NULL DEFAULT `false` | 02 明示 |
| `sale_channel` | `JSONB` | NOT NULL DEFAULT `'["web","h5","miniapp","app"]'::jsonb` | 02 明示 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 02 明示 |
| `published_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_spu_spu_no`：`UNIQUE (spu_no) WHERE deleted_at IS NULL`
- `ix_spu_shop_status`：`(shop_id, status, created_at DESC)`
- `ix_spu_merchant_id`：`(merchant_id, status)`
- `ix_spu_category_id`：`(category_id, status, sort_weight DESC)`
- `ix_spu_brand_id`：`(brand_id)`
- `ix_spu_audit_status`：`(audit_status, created_at DESC)`
- `ck_spu_status`、`ck_spu_audit_status`

### 3.7 `spu_attr_value`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `attr_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `value_id` | `UUID` | NULL（来自 `category_attr_value`） | 本 ST 提案 |
| `attr_value` | `TEXT` | NOT NULL | 本 ST 提案 |

索引与约束：

- `uq_spu_attr_value_spu_attr`：`UNIQUE (spu_id, attr_id) WHERE deleted_at IS NULL`——一个 SPU 一个属性一行，多值合并进 `attr_value`
- `ix_spu_attr_value_attr_id`：`(attr_id, value_id)`

### 3.8 `sku`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `spu_id` | `UUID` | NOT NULL | 02 明示 |
| `barcode` | `VARCHAR(64)` | NULL | 02 明示 |
| `spec_values` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 02 明示 |
| `image` | `TEXT` | NULL | 02 明示 |
| `weight_g` | `INTEGER` | NULL，CHECK `>= 0` | 02 明示 |
| `volume_cm3` | `INTEGER` | NULL，CHECK `>= 0` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/on_sale/off_sale/banned` | 02 明示字段，取值本 ST 提案 |
| `version` | `BIGINT` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（乐观锁） |

索引与约束：

- `uq_sku_sku_no`：`UNIQUE (sku_no) WHERE deleted_at IS NULL`
- `uq_sku_spu_barcode`：`UNIQUE (spu_id, barcode) WHERE barcode IS NOT NULL AND deleted_at IS NULL`
- `ix_sku_spu_id`：`(spu_id, status)`
- `ix_sku_barcode`：`(barcode) WHERE barcode IS NOT NULL AND deleted_at IS NULL`
- `ck_sku_status`、`ck_sku_weight_g`、`ck_sku_volume_cm3`、`ck_sku_version`

### 3.9 `sku_spec`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `attr_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `attr_value_id` | `UUID` | NULL | 本 ST 提案 |
| `spec_value` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |

索引与约束：

- `uq_sku_spec_sku_attr`：`UNIQUE (sku_id, attr_id) WHERE deleted_at IS NULL`
- `ix_sku_spec_attr_value_id`：`(attr_id, attr_value_id)`

### 3.10 `sku_media`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `media_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'image'`，CHECK ∈ `image/video` | 本 ST 提案 |
| `url` | `TEXT` | NOT NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `is_main` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |

索引与约束：

- `uq_sku_media_main`：`UNIQUE (sku_id) WHERE is_main AND deleted_at IS NULL`——每个 SKU 仅一张主图
- `ix_sku_media_sku_id`：`(sku_id, sort_weight)`
- `ck_sku_media_type`

### 3.11 `sku_price`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `price_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `list/sale/member/tier/activity/region` | 02 明示 |
| `price_amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 02 明示 |
| `min_qty` | `INTEGER` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 02 明示 |
| `max_qty` | `INTEGER` | NULL，CHECK `max_qty IS NULL OR max_qty >= min_qty` | 02 明示 |
| `region_code` | `VARCHAR(16)` | NULL | 02 明示 |
| `start_at` / `end_at` | `TIMESTAMPTZ` | NULL | 02 明示 |
| `currency` | `CHAR(3)` | NOT NULL DEFAULT `'CNY'` | 本 ST 提案（§2.0 币种约定） |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `ix_sku_price_sku_type_start`：`(sku_id, price_type, start_at)`（02 明示）
- `uq_sku_price_sku_type_region_start`：`UNIQUE (sku_id, price_type, region_code, start_at) NULLS NOT DISTINCT WHERE deleted_at IS NULL`——防同维度重复定价
- `ck_sku_price_type`、`ck_sku_price_amount`、`ck_sku_price_min_qty`、`ck_sku_price_max_qty`、`ck_sku_price_period`（`end_at IS NULL OR start_at IS NULL OR end_at >= start_at`）、`ck_sku_price_status`

### 3.12 `product_media`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `media_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'image'`，CHECK ∈ `image/video` | 本 ST 提案 |
| `url` | `TEXT` | NOT NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `is_main` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |

索引与约束：

- `uq_product_media_main`：`UNIQUE (spu_id) WHERE is_main AND deleted_at IS NULL`
- `ix_product_media_spu_id`：`(spu_id, sort_weight)`
- `ck_product_media_type`

### 3.13 `product_detail`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `content` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb`（结构化详情块快照） | 本 ST 提案 |
| `content_html` | `TEXT` | NULL | 本 ST 提案 |
| `version` | `INTEGER` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 本 ST 提案 |

索引与约束：

- `uq_product_detail_spu_id`：`UNIQUE (spu_id) WHERE deleted_at IS NULL`
- `ck_product_detail_version`

### 3.14 `product_audit`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `target_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `spu/media/detail` | 02 明示 |
| `target_id` | `UUID` | NOT NULL | 02 明示 |
| `round` | `SMALLINT` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 02 明示（计轮次） |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'submitted'`，CHECK ∈ `submitted/machine_reviewing/human_reviewing/approved/rejected/need_supplement` | 本 ST 提案（§2.13⑦ 状态机） |
| `result` | `VARCHAR(16)` | NULL，CHECK ∈ `approved/rejected/need_supplement` | 02 明示 |
| `reason_code` | `VARCHAR(64)` | NULL | 02 明示 |
| `reviewer_id` | `UUID` | NULL | 02 明示 |
| `machine_score` | `NUMERIC(5,2)` | NULL，CHECK `0 <= x <= 100` | 02 明示 |
| `reviewed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_product_audit_target_round`：`UNIQUE (target_type, target_id, round) WHERE deleted_at IS NULL`
- `ix_product_audit_target`：`(target_type, target_id, created_at DESC)`
- `ix_product_audit_status`：`(status, created_at)`
- `ck_product_audit_target_type`、`ck_product_audit_status`、`ck_product_audit_result`、`ck_product_audit_round`、`ck_product_audit_machine_score`

§2.13⑦ 的状态流转实现（Rust enum + 单测）不在本 ST（见 §7）。

### 3.15 `freight_template`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `charge_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'piece'`，CHECK ∈ `weight/piece/volume/amount` | 本 ST 提案 |
| `is_free` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `free_threshold_amount` | `NUMERIC(20,4)` | NULL，CHECK `>= 0` | 本 ST 提案（满额包邮） |
| `is_default` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_freight_template_merchant_name`：`UNIQUE (merchant_id, name) WHERE deleted_at IS NULL`
- `uq_freight_template_default`：`UNIQUE (merchant_id) WHERE is_default AND deleted_at IS NULL`
- `ix_freight_template_merchant_id`：`(merchant_id, status)`
- `ck_freight_template_charge_type`、`ck_freight_template_free_threshold`、`ck_freight_template_status`

### 3.16 `freight_template_rule`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `template_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `region_codes` | `JSONB` | NOT NULL DEFAULT `'[]'::jsonb`（地区编码列表，空表示全国默认） | 本 ST 提案 |
| `first_qty` | `NUMERIC(20,4)` | NOT NULL DEFAULT `1`，CHECK `> 0` | 本 ST 提案（首件/首重） |
| `first_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `extra_qty` | `NUMERIC(20,4)` | NOT NULL DEFAULT `1`，CHECK `> 0` | 本 ST 提案（续件/续重） |
| `extra_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `is_free` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |

索引与约束：

- `ix_freight_template_rule_template_id`：`(template_id, sort_weight)`
- `ck_freight_template_rule_first_qty`、`ck_freight_template_rule_first_amount`、`ck_freight_template_rule_extra_qty`、`ck_freight_template_rule_extra_amount`

### 3.17 `product_tag`

02 §2.3 只有表名，没有字典表。为了让 18 张表闭合且不新增表，本 ST 把 `product_tag` 设计为**商品-标签关联 + 标签展示名合一**的简化表（标注为本 ST 提案，待确认）：

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `tag_code` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `tag_name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `source` | `VARCHAR(16)` | NOT NULL DEFAULT `'merchant'`，CHECK ∈ `merchant/platform/ai` | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |

索引与约束：

- `uq_product_tag_spu_tag`：`UNIQUE (spu_id, tag_code) WHERE deleted_at IS NULL`
- `ix_product_tag_tag_code`：`(tag_code, spu_id)`
- `ck_product_tag_source`

### 3.18 `product_limit`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `scope` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `sku/spu/category/activity` | 02 明示 |
| `target_id` | `UUID` | NOT NULL | 本 ST 提案（按 `scope` 指向对应实体） |
| `limit_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `per_user/per_order/per_day` | 02 明示 |
| `limit_qty` | `INTEGER` | NOT NULL，CHECK `>= 1` | 02 明示 |
| `start_at` / `end_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_product_limit_scope_target_type`：`UNIQUE (scope, target_id, limit_type) WHERE deleted_at IS NULL`
- `ix_product_limit_target_id`：`(target_id, status)`
- `ck_product_limit_scope`、`ck_product_limit_type`、`ck_product_limit_qty`、`ck_product_limit_period`、`ck_product_limit_status`

### 3.19 `product_qa`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `spu_id` | `UUID` | NOT NULL | 02 明示 |
| `user_id` | `UUID` | NULL | 本 ST 提案 |
| `question` | `TEXT` | NOT NULL | 02 明示 |
| `answer` | `TEXT` | NULL | 02 明示 |
| `source` | `VARCHAR(16)` | NOT NULL DEFAULT `'user'`，CHECK ∈ `user/merchant/ai` | 02 明示 |
| `is_pinned` | `BOOLEAN` | NOT NULL DEFAULT `false` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'pending'`，CHECK ∈ `pending/answered/closed` | 本 ST 提案 |
| `answered_by` | `UUID` | NULL | 本 ST 提案 |
| `answered_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |

索引与约束：

- `ix_product_qa_spu_id`：`(spu_id, is_pinned DESC, created_at DESC)`
- `ix_product_qa_status`：`(status, created_at)`
- `ck_product_qa_source`、`ck_product_qa_status`

## 4. 迁移与种子设计

### 4.1 迁移命名

沿用 ADR-002 时间戳前缀，接在 `20261125112100` 之后，一表一迁移：

| 序号 | 版本前缀 | 主题 |
|---|---|---|
| 1 | `20261125112200` | `category` |
| 2 | `20261125112300` | `category_attr` |
| 3 | `20261125112400` | `category_attr_value` |
| 4 | `20261125112500` | `brand` |
| 5 | `20261125112600` | `spu` |
| 6 | `20261125112700` | `spu_attr_value` |
| 7 | `20261125112800` | `sku` |
| 8 | `20261125112900` | `sku_spec` |
| 9 | `20261125113000` | `sku_media` |
| 10 | `20261125113100` | `sku_price` |
| 11 | `20261125113200` | `product_media` |
| 12 | `20261125113300` | `product_detail` |
| 13 | `20261125113400` | `product_audit` |
| 14 | `20261125113500` | `freight_template` |
| 15 | `20261125113600` | `freight_template_rule` |
| 16 | `20261125113700` | `product_tag` |
| 17 | `20261125113800` | `product_limit` |
| 18 | `20261125113900` | `product_qa` |

`down.sql` 只 `DROP TABLE IF EXISTS` 本表，保证可从最新版本逐条回滚到 `20261125112100` 而互不牵连。

### 4.2 种子（已确认落地）

`scripts/seed_product_dict.sql`，非迁移、可重复执行：

- 类目树：3 个一级（数码/服饰/食品）+ 每类 2 个二级，共 9 条，`code` 固定、`path` 与 `level` 一致
- 品牌：5 条（含 `first_letter`）
- 类目属性模板：一级类目各 3 个属性 + `category_attr_value` 若干
- 主键确定性 UUID（`01930000-0000-7000-8000-` + 序号），全部 `ON CONFLICT DO NOTHING`
- 单事务，失败整体回滚

可选项：20 个示例商品（`spu` + `sku` + `sku_price`），依赖 ST-1.3 的 demo 商家/店铺；本批已确认纳入。

## 5. 验证

### 5.1 迁移可执行、可独立回滚（05 P1-1）

在空库 `ecom_p1_product` 上执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 依次回滚 product_qa → product_limit → ... → category
sqlx migrate run
```

断言：每次 `revert` 后仅目标表消失；ST-1.1/1.2/1.3 的 25 张表始终存在；再次 `run` 后 43 张表全部恢复。

### 5.2 约束断言（05 P1-2 的商品域部分）

在 `scripts/verify_p1_constraints.sql` 追加第四段：

1. 18 张表存在
2. 软删部分唯一索引存在且唯一：`uq_category_code`、`uq_category_attr_category_code`、`uq_category_attr_value_attr_value`、`uq_brand_name`、`uq_spu_spu_no`、`uq_spu_attr_value_spu_attr`、`uq_sku_sku_no`、`uq_sku_spu_barcode`、`uq_sku_spec_sku_attr`、`uq_sku_media_main`、`uq_product_media_main`、`uq_product_detail_spu_id`、`uq_product_audit_target_round`、`uq_freight_template_merchant_name`、`uq_product_tag_spu_tag`、`uq_product_limit_scope_target_type`
3. 条件唯一索引额外带业务过滤条件：`uq_sku_media_main` / `uq_product_media_main`（含 `is_main`）、`uq_freight_template_default`（含 `is_default`）
4. `uq_sku_price_sku_type_region_start` 唯一、带软删条件且 `indnullsnotdistinct = true`
5. 关键 CHECK 存在，且非法写入被拒绝：
   - `spu.status='bogus'`、`sku.version=-1`
   - `sku_price.price_amount=-1`、`sku_price.max_qty < min_qty`
   - `product_audit.machine_score=101`
   - `product_limit.limit_qty=0`
   - `freight_template_rule.first_qty=0`
6. `spu.sale_channel` 默认值与 `NUMERIC` 精度：`sku_price.price_amount` = `(20,4)`、`product_audit.machine_score` = `(5,2)`

### 5.3 种子幂等（05 P1-3 的商品域部分，若确认种子）

```powershell
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_product_dict.sql   # 第一次
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_product_dict.sql   # 第二次
```

断言：类目/品牌/属性行数两次一致，`code` 哈希一致；若含示例商品，`spu` / `sku` / `sku_price` 行数不变。

### 5.4 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 退出码 0（本 ST 不改 Rust）
- `git diff --check` 退出码 0；`git status --short` 全部落在白名单内

## 6. 文件白名单

新增：

- `specs/ST-1.4.md`
- `migrations/20261125112200`~`20261125113900` 共 18 组 `{up,down}.sql`
- `scripts/seed_product_dict.sql`

修改：

- `scripts/verify_p1_constraints.sql`（追加商品域断言段，保留前三段不变）
- `docs/gates/P1.md`（追加 ST-1.4 证据）

明确不改：`apps/**`、`crates/**`、`Cargo.toml`、`Cargo.lock`、`deploy/**`、`docs/adr/**`、`docs/spec/**`、`docs/prompt/MAIN.md`、`docs/tech-debt.md`、`docs/gates/P0.md`、既有 59 个迁移。

## 7. 已确认的决策点

用户已确认：18 张一次交付、种子含字典 + 20 个示例商品、`product_tag` 采用关联 + 展示名合并、商品审核状态机（02 §2.13⑦）本批不产出。

1. **批次范围**：18 张一次交付（默认），或拆成「基础 6 张（category/brand/spu/sku/product_media/product_detail）」+「规格价格 6 张（spu_attr_value/sku_spec/sku_media/sku_price/product_audit/product_tag）」+「运营 6 张（freight_template/freight_template_rule/product_limit/product_qa + …）」。
2. **种子范围**：仅字典（类目树/品牌/属性模板），或额外包含 20 个示例商品。
3. **`product_tag` 语义**：合并「标签字典 + 商品关联」为一张表（默认），或只建关联（`spu_id + tag_code`，展示名由前端字典维护）。
4. **商品审核状态机**：02 §2.13⑦ 属于 12 套状态机之一。本 ST 默认只建 `status/result` 列与 CHECK，Rust enum + 迁移矩阵单测留待专门的「状态机批」（P1-4）；若要求本批产出，会改动 `crates/**` 并扩大白名单。

## 8. 完成定义

- 18 条迁移在空库 up 成功，可逐条 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误，前三段仍通过
- （若确认）商品字典种子连续两次执行结果一致
- `docs/gates/P1.md` 记录命令、退出码与断言结论，并更新 P1-1/P1-2/P1-3 进度
- 三条 Rust 门禁仍全绿，无白名单外改动
- 不声称商品发布/审核流转/价格计算/运费试算或任何库存、交易域表已完成
