# ST-1.5 · 库存与供应链域表（21 张）

- 阶段：P1 / ST-1.5（P1 第 5 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.4、§2.13⑧⑨⑩、§2.15、§2.16；05 §P1 Gate 2、§P4；ADR-002
- 前置：ST-1.1 ~ ST-1.4 已完成并推送（`83c476a`）

## 1. 背景与目标

商品域已有 `sku`，但没有库存就下不了单：P5 交易的下单链路依赖 `sku_stock` 的原子扣减与 `stock_reserve` 的预占，P4 Gate 的「三段数量守恒」「1000 并发抢 100 库存」「盘点差异必须生成流水」全部建立在本批表结构上。05 Gate P1-2 还点名要求 `sku_stock` 的三个 CHECK。

本 ST 只交付**表结构、约束、索引、可回滚迁移、约束断言**（以及用户确认后的仓库/库存种子），不交付库存扣减、预占、调拨、盘点、采购、入库、结算等业务逻辑。

**数量差异提示**：02 §2.4 标题写「20 张」，但正文列举的库存 11 张 + 供应链 10 张 = **21 张**。本 Spec 按正文清单交付 21 张（见 §7 决策点 1）。

## 2. 范围

### 包含

1. 21 张表，一表一迁移（`up` / `down` 各一文件），编号接在 `20261125113900` 之后：
   - 库存 11：`warehouse`、`warehouse_zone`、`sku_stock`、`sku_stock_batch`、`stock_log`、`stock_reserve`、`stock_allocate_rule`、`transfer_order`、`transfer_order_item`、`stock_count`、`stock_count_item`
   - 供应链 10：`supplier`、`supplier_sku`、`purchase_order`、`purchase_order_item`、`inbound_order`、`inbound_order_item`、`purchase_return`、`supplier_settlement`、`supplier_payment`、`production_order`
2. 扩展 `scripts/verify_p1_constraints.sql`：追加库存与供应链域的存在性、部分唯一索引、CHECK、数量/金额非负与守恒断言
3. 更新 `docs/gates/P1.md`：追加本批空库 up / 逐条 down / 再 up 与断言实测结果
4. 本 Spec 文件本身
5. `scripts/seed_warehouse_demo.sql`（demo 仓库 + 库区 + 20 个示例 SKU 初始库存）
6. 02 §2.13⑧⑨⑩ 三套状态机的 Rust 实现与单测：`crates/domain/src/inventory.rs`，`enum Status` + `fn transition`，覆盖全部合法迁移与全部非法组合

### 不包含（明确不做）

- 不写 02 §2.13 其余 9 套状态机（订单/支付/退款/售后/结算/分账/审核/优惠券/会员订阅，P1-4 交付）；不改 `crates/**` 中除 `domain` 外的任何文件
- 不写库存扣减、预占、释放、跨仓分配、调拨、盘点、采购审批、入库、退货、供应商结算与付款、生产工单等业务逻辑（P4/P9）
- 不建交易 / 营销 / 内容 / AI 表；不建 `settlement_order`（商家结算，P9）
- 不建 `region_dict`；`warehouse_zone.region_codes` 用 JSONB 字符串弱引用
- 不建 `audit_log` 业务审计扩展与月分区（沿用 ST-1.2 决策点）
- 不写 `scripts/consistency_check.sql`（依赖订单/分账/结算表）
- 不改既有 79 个迁移文件与 `docs/spec/**`、`docs/prompt/MAIN.md`

## 3. 字段定义

### 3.1 来源标注规则

02 §2.4 只对 `sku_stock`、`sku_stock_batch`、`stock_reserve`、`stock_log`、`purchase_order`、`purchase_order_item` 给出字段级要点，其余 15 张仅给表名。标注两列：

- **02 明示**：文档已写明的字段与约束，不得偏离
- **本 ST 提案**：按 §2.0 命名规范补齐的最小必要字段，**经用户确认后落地**；后续只能追加列，不能改名改语义

所有表均具备 `id UUID PRIMARY KEY`、`created_at`、`updated_at`、`deleted_at`（§2.0 通用列），`id` 由应用层生成 UUIDv7，DDL 不设默认值。

所有表**不建物理外键**（§2.0 第 3 条）：`sku_id` / `warehouse_id` / `supplier_id` 等跨表引用由应用层校验 + 巡检保证，保证每张迁移可独立回滚。

金额 `NUMERIC(20,4)`；数量 `INTEGER`（库存件数）或 `NUMERIC(20,4)`（重量/体积类，本批未用）；乐观锁 `version BIGINT`。

`stock_log` 语义上「只增不改」，但仍保留 `deleted_at` 通用列（与 `audit_log` 一致），由应用层保证不写软删。

### 3.2 `warehouse`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `warehouse_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `type` | `VARCHAR(16)` | NOT NULL DEFAULT `'normal'`，CHECK ∈ `normal/bonded/virtual` | 本 ST 提案 |
| `province` / `city` / `district` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `address` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `contact_name` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `contact_phone` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `is_default` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `sort_weight` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_warehouse_no`：`UNIQUE (warehouse_no) WHERE deleted_at IS NULL`
- `uq_warehouse_default`：`UNIQUE (merchant_id) WHERE is_default AND deleted_at IS NULL`——每商家一个默认仓
- `ix_warehouse_merchant_id`：`(merchant_id, status)`
- `ck_warehouse_type`、`ck_warehouse_status`

### 3.3 `warehouse_zone`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `zone_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `region_codes` | `JSONB` | NOT NULL DEFAULT `'[]'::jsonb`（配送区域编码列表，空表示不限制） | 本 ST 提案 |
| `priority` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_warehouse_zone_warehouse_zone_no`：`UNIQUE (warehouse_id, zone_no) WHERE deleted_at IS NULL`
- `ix_warehouse_zone_warehouse_id`：`(warehouse_id, priority)`
- `ck_warehouse_zone_status`

### 3.4 `sku_stock`（02 明示字段级）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `warehouse_id` | `UUID` | NOT NULL | 02 明示 |
| `available_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（≥0） |
| `locked_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（≥0） |
| `occupied_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（≥0） |
| `safety_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（≥0，低于触发预警） |
| `version` | `BIGINT` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示（乐观锁） |

索引与约束：

- `uq_sku_stock_sku_warehouse`：`UNIQUE (sku_id, warehouse_id) WHERE deleted_at IS NULL`（02 明示「`(sku_id, warehouse_id)` 唯一」）
- `ck_sku_stock_available_qty`、`ck_sku_stock_locked_qty`、`ck_sku_stock_occupied_qty`（**05 P1-2 点名的三个 CHECK**）、`ck_sku_stock_safety_qty`、`ck_sku_stock_version`

> `updated_at` 由通用列提供，02 明示；不加额外触发器，由应用层在每次扣减时同步更新。

### 3.5 `sku_stock_batch`（02 明示）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `warehouse_id` | `UUID` | NOT NULL | 02 明示 |
| `batch_no` | `VARCHAR(64)` | NOT NULL | 02 明示 |
| `production_at` | `DATE` | NULL | 02 明示 |
| `expire_at` | `DATE` | NULL | 02 明示 |
| `qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'normal'`，CHECK ∈ `normal/frozen/expired` | 本 ST 提案 |

索引与约束：

- `uq_sku_stock_batch_sku_warehouse_batch`：`UNIQUE (sku_id, warehouse_id, batch_no) WHERE deleted_at IS NULL`
- `ix_sku_stock_batch_expire_at`：`(expire_at) WHERE expire_at IS NOT NULL AND deleted_at IS NULL`——近效期预警扫描
- `ck_sku_stock_batch_qty`、`ck_sku_stock_batch_period`（`production_at IS NULL OR expire_at IS NULL OR expire_at >= production_at`）、`ck_sku_stock_batch_status`

### 3.6 `stock_log`（02 明示，只增不改）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `warehouse_id` | `UUID` | NOT NULL | 02 明示 |
| `change_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `inbound/outbound/reserve/confirm/release/adjust/count/transfer` | 02 明示 |
| `delta_available` | `INTEGER` | NOT NULL DEFAULT `0` | 02 明示 |
| `delta_locked` | `INTEGER` | NOT NULL DEFAULT `0` | 02 明示 |
| `delta_occupied` | `INTEGER` | NOT NULL DEFAULT `0` | 02 明示 |
| `biz_no` | `VARCHAR(64)` | NULL | 02 明示 |
| `operator_id` | `UUID` | NULL | 02 明示 |
| `remark` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `ix_stock_log_sku_warehouse_created`：`(sku_id, warehouse_id, created_at DESC)`
- `ix_stock_log_biz_no`：`(biz_no) WHERE biz_no IS NOT NULL AND deleted_at IS NULL`
- `ck_stock_log_change_type`

> 02 要求「按月分区」。本批是否分区见 §7 决策点 3；默认先建普通表，分区随 P4 并发压测一并决策。

### 3.7 `stock_reserve`（02 明示）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `reserve_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `biz_type` | `VARCHAR(16)` | NOT NULL，CHECK ∈ `order/seckill/transfer` | 02 明示 |
| `biz_no` | `VARCHAR(64)` | NOT NULL | 02 明示 |
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `warehouse_id` | `UUID` | NOT NULL | 02 明示 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 02 明示 |
| `status` | `VARCHAR(16)` | NOT NULL DEFAULT `'reserved'`，CHECK ∈ `reserved/confirmed/released` | 02 明示 |
| `expire_at` | `TIMESTAMPTZ` | NULL | 02 明示 |

索引与约束：

- `uq_stock_reserve_reserve_no`：`UNIQUE (reserve_no) WHERE deleted_at IS NULL`（02 明示）
- `uq_stock_reserve_biz`：`UNIQUE (biz_no, sku_id, warehouse_id, status) WHERE deleted_at IS NULL`（02 明示，防重复预占）
- `ix_stock_reserve_expire_at`：`(expire_at) WHERE status = 'reserved' AND deleted_at IS NULL`
- `ck_stock_reserve_biz_type`、`ck_stock_reserve_qty`、`ck_stock_reserve_status`

### 3.8 `stock_allocate_rule`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `merchant_id` | `UUID` | NULL（平台级规则为空） | 本 ST 提案 |
| `warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `rule_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'priority'`，CHECK ∈ `priority/region/split` | 本 ST 提案 |
| `region_codes` | `JSONB` | NOT NULL DEFAULT `'[]'::jsonb` | 本 ST 提案 |
| `min_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `priority` | `INTEGER` | NOT NULL DEFAULT `0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `ix_stock_allocate_rule_warehouse_id`：`(warehouse_id, priority)`
- `ix_stock_allocate_rule_merchant_id`：`(merchant_id) WHERE merchant_id IS NOT NULL AND deleted_at IS NULL`
- `ck_stock_allocate_rule_type`、`ck_stock_allocate_rule_min_qty`、`ck_stock_allocate_rule_status`

### 3.9 `transfer_order`（§2.13⑨）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `transfer_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `from_warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `to_warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'created'`，CHECK ∈ `created/approved/outbound/in_transit/inbound/completed/cancelled` | 本 ST 提案（§2.13⑨） |
| `total_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `reason` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `expected_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `completed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_transfer_order_no`：`UNIQUE (transfer_no) WHERE deleted_at IS NULL`
- `ix_transfer_order_status`：`(status, created_at DESC)`
- `ix_transfer_order_from_warehouse_id`：`(from_warehouse_id, status)`
- `ix_transfer_order_to_warehouse_id`：`(to_warehouse_id, status)`
- `ck_transfer_order_status`、`ck_transfer_order_total_qty`、`ck_transfer_order_distinct_warehouse`（`from_warehouse_id <> to_warehouse_id`）

### 3.10 `transfer_order_item`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `transfer_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `batch_no` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `received_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND <= qty` | 本 ST 提案 |

索引与约束：

- `uq_transfer_order_item_no_sku_batch`：`UNIQUE (transfer_no, sku_id, batch_no) NULLS NOT DISTINCT WHERE deleted_at IS NULL`
- `ck_transfer_order_item_qty`、`ck_transfer_order_item_received_qty`

### 3.11 `stock_count`（§2.13⑩）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `count_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'created'`，CHECK ∈ `created/counting/submitted/reviewed/adjusted/closed` | 本 ST 提案（§2.13⑩） |
| `count_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'full'`，CHECK ∈ `full/partial` | 本 ST 提案 |
| `operator_id` | `UUID` | NULL | 本 ST 提案 |
| `started_at` / `finished_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `remark` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_stock_count_no`：`UNIQUE (count_no) WHERE deleted_at IS NULL`
- `ix_stock_count_warehouse_id`：`(warehouse_id, status)`
- `ck_stock_count_status`、`ck_stock_count_type`

### 3.12 `stock_count_item`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `count_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `batch_no` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `book_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `actual_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `diff_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `= actual_qty - book_qty` | 本 ST 提案 |

索引与约束：

- `uq_stock_count_item_no_sku_batch`：`UNIQUE (count_no, sku_id, batch_no) NULLS NOT DISTINCT WHERE deleted_at IS NULL`
- `ck_stock_count_item_book_qty`、`ck_stock_count_item_actual_qty`、`ck_stock_count_item_diff`（强制 `diff_qty = actual_qty - book_qty`，对应 §2.13⑩「差异必须走 adjust 生成 `stock_log`」的数据前提）

### 3.13 `supplier`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `supplier_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |
| `type` | `VARCHAR(16)` | NOT NULL DEFAULT `'company'`，CHECK ∈ `personal/company` | 本 ST 提案 |
| `contact_name` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `contact_phone` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `address` | `VARCHAR(255)` | NULL | 本 ST 提案 |
| `settle_cycle` | `VARCHAR(16)` | NOT NULL DEFAULT `'T+1'`，CHECK ∈ `T+1/T+7/T+15/T+30` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `applying/active/suspended/closed` | 本 ST 提案 |

索引与约束：

- `uq_supplier_no`：`UNIQUE (supplier_no) WHERE deleted_at IS NULL`
- `ix_supplier_merchant_id`：`(merchant_id, status)`
- `ck_supplier_type`、`ck_supplier_settle_cycle`、`ck_supplier_status`

### 3.14 `supplier_sku`（供货关系与供货价）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `supplier_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `supply_price` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 本 ST 提案 |
| `currency` | `CHAR(3)` | NOT NULL DEFAULT `'CNY'` | 本 ST 提案（§2.0） |
| `min_order_qty` | `INTEGER` | NOT NULL DEFAULT `1`，CHECK `>= 1` | 本 ST 提案 |
| `lead_time_days` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `is_primary` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/disabled` | 本 ST 提案 |

索引与约束：

- `uq_supplier_sku_supplier_sku`：`UNIQUE (supplier_id, sku_id) WHERE deleted_at IS NULL`
- `uq_supplier_sku_primary`：`UNIQUE (sku_id) WHERE is_primary AND deleted_at IS NULL`——每个 SKU 一个主供应商
- `ix_supplier_sku_sku_id`：`(sku_id, status)`
- `ck_supplier_sku_supply_price`、`ck_supplier_sku_min_order_qty`、`ck_supplier_sku_lead_time_days`、`ck_supplier_sku_status`

### 3.15 `purchase_order`（02 明示 + §2.13⑧）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `po_no` | `VARCHAR(32)` | NOT NULL | 02 明示（唯一） |
| `supplier_id` | `UUID` | NOT NULL | 02 明示 |
| `warehouse_id` | `UUID` | NOT NULL | 02 明示 |
| `merchant_id` | `UUID` | NOT NULL | 本 ST 提案（归属校验） |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/approving/approved/ordered/partially_received/received/settled/closed/cancelled` | 02 明示字段 + §2.13⑧ 取值 |
| `total_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `expected_at` | `TIMESTAMPTZ` | NULL | 02 明示 |
| `approved_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `remark` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_purchase_order_no`：`UNIQUE (po_no) WHERE deleted_at IS NULL`
- `ix_purchase_order_supplier_id`：`(supplier_id, status)`
- `ix_purchase_order_status`：`(status, created_at DESC)`
- `ck_purchase_order_status`、`ck_purchase_order_total_amount`

### 3.16 `purchase_order_item`（02 明示）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `po_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 02 明示 |
| `received_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND <= qty` | 02 明示 |
| `price_amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 02 明示 |

索引与约束：

- `uq_purchase_order_item_po_sku`：`UNIQUE (po_no, sku_id) WHERE deleted_at IS NULL`
- `ck_purchase_order_item_qty`、`ck_purchase_order_item_received_qty`、`ck_purchase_order_item_price_amount`

### 3.17 `inbound_order`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `inbound_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `supplier_id` | `UUID` | NULL | 本 ST 提案 |
| `po_no` | `VARCHAR(32)` | NULL（关联采购单） | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/pending/receiving/completed/cancelled` | 本 ST 提案 |
| `total_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `received_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `operator_id` | `UUID` | NULL | 本 ST 提案 |

索引与约束：

- `uq_inbound_order_no`：`UNIQUE (inbound_no) WHERE deleted_at IS NULL`
- `ix_inbound_order_po_no`：`(po_no) WHERE po_no IS NOT NULL AND deleted_at IS NULL`
- `ix_inbound_order_warehouse_id`：`(warehouse_id, status)`
- `ck_inbound_order_status`、`ck_inbound_order_total_qty`

### 3.18 `inbound_order_item`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `inbound_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `batch_no` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `received_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND <= qty` | 本 ST 提案 |
| `price_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `production_at` / `expire_at` | `DATE` | NULL | 本 ST 提案 |

索引与约束：

- `uq_inbound_order_item_no_sku_batch`：`UNIQUE (inbound_no, sku_id, batch_no) NULLS NOT DISTINCT WHERE deleted_at IS NULL`
- `ck_inbound_order_item_qty`、`ck_inbound_order_item_received_qty`、`ck_inbound_order_item_price_amount`、`ck_inbound_order_item_period`

### 3.19 `purchase_return`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `return_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `po_no` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `inbound_no` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `supplier_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `warehouse_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/submitted/approved/shipped/completed/cancelled` | 本 ST 提案 |
| `total_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `total_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `reason` | `VARCHAR(255)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_purchase_return_no`：`UNIQUE (return_no) WHERE deleted_at IS NULL`
- `ix_purchase_return_supplier_id`：`(supplier_id, status)`
- `ck_purchase_return_status`、`ck_purchase_return_total_qty`、`ck_purchase_return_total_amount`

### 3.20 `supplier_settlement`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `settlement_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `supplier_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `period_start` / `period_end` | `DATE` | NOT NULL | 本 ST 提案 |
| `gross_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `return_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `net_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `= gross_amount - return_amount` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'generated'`，CHECK ∈ `generated/confirmed/paying/paid/closed` | 本 ST 提案 |
| `paid_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_supplier_settlement_no`：`UNIQUE (settlement_no) WHERE deleted_at IS NULL`
- `uq_supplier_settlement_supplier_period`：`UNIQUE (supplier_id, period_start, period_end) WHERE deleted_at IS NULL`
- `ck_supplier_settlement_period`（`period_end >= period_start`）、`ck_supplier_settlement_gross_amount`、`ck_supplier_settlement_return_amount`、`ck_supplier_settlement_net_amount`、`ck_supplier_settlement_status`

### 3.21 `supplier_payment`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `payment_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `supplier_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `settlement_no` | `VARCHAR(32)` | NULL | 本 ST 提案 |
| `amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `currency` | `CHAR(3)` | NOT NULL DEFAULT `'CNY'` | 本 ST 提案（§2.0） |
| `pay_method` | `VARCHAR(16)` | NOT NULL DEFAULT `'bank'`，CHECK ∈ `bank/alipay/wechat/offset` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'pending'`，CHECK ∈ `pending/paying/success/failed` | 本 ST 提案 |
| `channel_txn_id` | `VARCHAR(128)` | NULL | 本 ST 提案 |
| `paid_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_supplier_payment_no`：`UNIQUE (payment_no) WHERE deleted_at IS NULL`
- `uq_supplier_payment_channel_txn`：`UNIQUE (pay_method, channel_txn_id) WHERE channel_txn_id IS NOT NULL AND deleted_at IS NULL`——防重复出账
- `ix_supplier_payment_settlement_no`：`(settlement_no) WHERE settlement_no IS NOT NULL AND deleted_at IS NULL`
- `ck_supplier_payment_amount`、`ck_supplier_payment_method`、`ck_supplier_payment_status`

### 3.22 `production_order`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `production_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `supplier_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `completed_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND <= qty` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'draft'`，CHECK ∈ `draft/in_production/completed/cancelled` | 本 ST 提案 |
| `expected_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `started_at` / `completed_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_production_order_no`：`UNIQUE (production_no) WHERE deleted_at IS NULL`
- `ix_production_order_supplier_id`：`(supplier_id, status)`
- `ix_production_order_sku_id`：`(sku_id, status)`
- `ck_production_order_qty`、`ck_production_order_completed_qty`、`ck_production_order_status`

## 4. 迁移与种子设计

### 4.1 迁移命名

沿用 ADR-002 时间戳前缀，接在 `20261125113900` 之后，一表一迁移：

| 序号 | 版本前缀 | 主题 |
|---|---|---|
| 1 | `20261125114000` | `warehouse` |
| 2 | `20261125114100` | `warehouse_zone` |
| 3 | `20261125114200` | `sku_stock` |
| 4 | `20261125114300` | `sku_stock_batch` |
| 5 | `20261125114400` | `stock_log` |
| 6 | `20261125114500` | `stock_reserve` |
| 7 | `20261125114600` | `stock_allocate_rule` |
| 8 | `20261125114700` | `transfer_order` |
| 9 | `20261125114800` | `transfer_order_item` |
| 10 | `20261125114900` | `stock_count` |
| 11 | `20261125115000` | `stock_count_item` |
| 12 | `20261125115100` | `supplier` |
| 13 | `20261125115200` | `supplier_sku` |
| 14 | `20261125115300` | `purchase_order` |
| 15 | `20261125115400` | `purchase_order_item` |
| 16 | `20261125115500` | `inbound_order` |
| 17 | `20261125115600` | `inbound_order_item` |
| 18 | `20261125115700` | `purchase_return` |
| 19 | `20261125115800` | `supplier_settlement` |
| 20 | `20261125115900` | `supplier_payment` |
| 21 | `20261125116000` | `production_order` |

`down.sql` 只 `DROP TABLE IF EXISTS` 本表，保证可从最新版本逐条回滚到 `20261125113900` 而互不牵连。

### 4.2 约束命名汇总（供断言脚本使用）

- 软删部分唯一索引 20 组：`uq_warehouse_no`、`uq_warehouse_zone_warehouse_zone_no`、`uq_sku_stock_sku_warehouse`、`uq_sku_stock_batch_sku_warehouse_batch`、`uq_stock_reserve_reserve_no`、`uq_stock_reserve_biz`、`uq_transfer_order_no`、`uq_transfer_order_item_no_sku_batch`、`uq_stock_count_no`、`uq_stock_count_item_no_sku_batch`、`uq_supplier_no`、`uq_supplier_sku_supplier_sku`、`uq_purchase_order_no`、`uq_purchase_order_item_po_sku`、`uq_inbound_order_no`、`uq_inbound_order_item_no_sku_batch`、`uq_purchase_return_no`、`uq_supplier_settlement_no`、`uq_supplier_settlement_supplier_period`、`uq_supplier_payment_no`
- 条件唯一索引 4 组：`uq_warehouse_default`（`is_default`）、`uq_supplier_sku_primary`（`is_primary`）、`uq_supplier_payment_channel_txn`（`channel_txn_id IS NOT NULL`）
- `NULLS NOT DISTINCT` 唯一索引 3 组：`uq_transfer_order_item_no_sku_batch`、`uq_stock_count_item_no_sku_batch`、`uq_inbound_order_item_no_sku_batch`
- `sku_stock` 三个 CHECK：`ck_sku_stock_available_qty`、`ck_sku_stock_locked_qty`、`ck_sku_stock_occupied_qty`（05 P1-2 点名）

### 4.3 种子（已确认落地）

`scripts/seed_warehouse_demo.sql`，非迁移、可重复执行、单事务：

- demo 仓库 1 个（`W_DEMO_0001`，绑定 ST-1.3 的 `M_DEMO_0001`）+ 库区 1 个（`Z_DEMO_0001`）
- 若 ST-1.4 的 20 个示例 SKU 存在，则为每个 SKU 建一条 `sku_stock`（`available_qty = 1000`，`safety_qty = 50`）
- 主键确定性 UUID（`01930000-0000-7000-8000-` + 序号），全部 `ON CONFLICT DO NOTHING`
- 演示商家/商品缺失时自动插入 0 行，不产生孤儿数据

## 5. 验证

### 5.1 迁移可执行、可独立回滚（05 P1-1）

在空库 `ecom_p1_stock` 上执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 依次回滚 production_order → ... → warehouse
sqlx migrate run
```

断言：每次 `revert` 后仅目标表消失；前四批 43 张表始终存在；再次 `run` 后 64 张表全部恢复。

### 5.2 约束断言（05 P1-2 的库存部分）

在 `scripts/verify_p1_constraints.sql` 追加第五段：

1. 21 张表存在
2. 20 组软删部分唯一索引唯一且带 `WHERE deleted_at IS NULL`
3. 3 组条件唯一索引额外带业务过滤条件（`is_default`、`is_primary`、`channel_txn_id IS NOT NULL`）
4. 3 组 `indnullsnotdistinct = true`
5. **`sku_stock` 三个 CHECK 存在**（05 P1-2 原文要求）
6. 关键 CHECK 存在，且非法写入被拒绝：
   - `sku_stock.available_qty=-1`、`locked_qty=-1`、`occupied_qty=-1`
   - `stock_reserve.qty=0`、非法 `status`
   - `transfer_order.from_warehouse_id = to_warehouse_id`
   - `stock_count_item.diff_qty` 与 `actual_qty - book_qty` 不一致
   - `purchase_order_item.received_qty > qty`
   - `supplier_payment.amount=0`
   - `supplier_settlement.net_amount <> gross_amount - return_amount`
7. 数量守恒与重复预占：
   - 同一 `(sku_id, warehouse_id)` 插入两条 `sku_stock` 被唯一索引拒绝
   - 同一 `(biz_no, sku_id, warehouse_id, status)` 重复预占被唯一索引拒绝
   - 同一 `(pay_method, channel_txn_id)` 重复出账被唯一索引拒绝
8. 精度：`supplier_sku.supply_price` = `NUMERIC(20,4)`、`purchase_order.total_amount` = `NUMERIC(20,4)`

### 5.3 种子幂等

```powershell
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_warehouse_demo.sql   # 第一次
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_warehouse_demo.sql   # 第二次
```

断言：`warehouse` / `warehouse_zone` / `sku_stock` 行数两次一致，`warehouse_no` 哈希一致。

### 5.4 状态机单测（05 P1-4 的本批部分）

`crates/domain/src/inventory.rs` 三套状态机各一组测试：

1. 合法迁移全过：逐条断言 `(from, action) -> Ok(to)`
2. 非法迁移全错：遍历「全部状态 × 全部动作」矩阵，凡不在合法表的组合必须返回 `Err(InvalidTransition)`
3. 覆盖 02 §2.13 的关键约束：采购单仅 `approved` 可取消、调拨单出库后不可取消、盘点单必须 `reviewed → adjusted → closed`

### 5.5 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 退出码 0（本 ST 新增 `domain` 单测，用例数增加）
- `git diff --check` 退出码 0；`git status --short` 全部落在白名单内

## 6. 文件白名单

新增：

- `specs/ST-1.5.md`
- `migrations/20261125114000`~`20261125116000` 共 21 组 `{up,down}.sql`
- `scripts/seed_warehouse_demo.sql`
- `crates/domain/src/inventory.rs`（3 套状态机 + 单测）

修改：

- `scripts/verify_p1_constraints.sql`（追加库存与供应链域断言段，保留前四段不变）
- `docs/gates/P1.md`（追加 ST-1.5 证据）
- `crates/domain/src/lib.rs`（`pub mod inventory;`）
- `crates/domain/Cargo.toml`（加入 `thiserror.workspace = true`）
- `Cargo.lock`（`domain` 包新增 `thiserror` 依赖条目，共 3 行）

明确不改：`apps/**`、`crates/**` 中除 `domain` 外的部分、根 `Cargo.toml`、`deploy/**`、`docs/adr/**`、`docs/spec/**`、`docs/prompt/MAIN.md`、`docs/tech-debt.md`、`docs/gates/P0.md`、既有 79 个迁移。

## 7. 已确认的决策点

用户已确认：

1. **批次范围**：02 §2.4 标题写「20 张」，正文实为 21 张，按正文 **21 张一次交付**。
2. **种子范围**：`warehouse` + `warehouse_zone` + 20 个示例 SKU 的 `sku_stock`（`available_qty=1000`、`safety_qty=50`）。
3. **`stock_log` 分区**：本批建**普通表**，按月分区随 P4 并发压测一并落地（与 `audit_log` 的既有决策一致）。
4. **三套状态机**：本批**同时产出** Rust `enum` + 单测（`crates/domain/src/inventory.rs`），白名单相应扩大至 `crates/domain/**`。

## 8. 完成定义

- 21 条迁移在空库 up 成功，可逐条 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误，前四段仍通过；`sku_stock` 三个 CHECK 断言通过
- 仓库/库存种子连续两次执行结果一致
- 三套状态机单测全绿：合法迁移全过、非法组合全错
- `docs/gates/P1.md` 记录命令、退出码与断言结论，并更新 P1-1/P1-2/P1-3/P1-4 进度
- 三条 Rust 门禁仍全绿，无白名单外改动
- 不声称库存扣减、预占、调拨、盘点、采购、入库、结算或任何交易/营销域逻辑已完成
