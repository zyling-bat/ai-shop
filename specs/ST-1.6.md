# ST-1.6 · 交易域表（12 张）

- 阶段：P1 / ST-1.6（P1 第 6 批）
- 日期：2026-11-25
- 依据：02 §2.0、§2.5、§2.13①、§2.15、§2.16；05 §P1 Gate 2、§P1 Gate 4；ADR-002
- 前置：ST-1.1 ~ ST-1.5 已完成并推送（`12d7fa0`）

## 1. 背景与目标

商品、商家、库存三域已就位，但「用户下不了单」：P5 交易的全部链路（购物车 → 下单 → 支付回调 → 发货 → 收货 → 完成）都建立在本批表结构上。05 Gate P1-2 点名要求「订单号唯一索引」，P1-4 还差订单状态机（02 §2.13①），P1-5 的「`Σ order_item.amount = order.goods_amount`」也首次具备可执行前提（但另两条依赖分账/结算表，仍不能收口）。

本 ST 只交付**表结构、约束、索引、可回滚迁移、约束断言、订单状态机**（以及用户确认后的交易域种子），不交付购物车、下单、支付、发货、收货、开票、价格计算等业务逻辑。

## 2. 范围

### 包含

1. 12 张表，一表一迁移（`up` / `down` 各一文件），编号接在 `20261125116000` 之后：
   - 购物车 2：`cart`、`cart_item`
   - 订单主链 6：`"order"`、`order_item`、`order_amount_snapshot`、`order_address`、`order_status_log`、`order_remark`
   - 订单扩展与票据 4：`order_tag`、`invoice`、`invoice_item`、`price_calc_log`
2. 扩展 `scripts/verify_p1_constraints.sql`：追加交易域存在性、部分唯一索引、CHECK、金额/数量非负与重复单号断言
3. 更新 `docs/gates/P1.md`：追加本批空库 up / 逐条 down / 再 up 与断言实测结果
4. 02 §2.13① 订单状态机的 Rust 实现与单测：`crates/domain/src/trade.rs`
5. 本 Spec 文件本身
6. `scripts/seed_trade_demo.sql`（demo 购物车 + 1 笔已支付订单及主链条数据，范围待确认）

### 不包含（明确不做）

- 不写 02 §2.13 其余 8 套状态机（支付/退款/售后/结算/分账/审核/优惠券/会员订阅）
- 不写购物车增删改、下单编排、支付回调、发货、收货、自动完成、开票、价格计算引擎等业务逻辑（P5/P6/P9）
- 不建支付域（`payment_order` 等 10 张）、履约域（`delivery_order` 等 8 张）、售后域（`after_sale_order` 等 8 张）、营销域（`coupon` 等 14 张）
- 不建 `settlement_order` / `split_instruction` / `fund_flow` 等结算财务表；P1-5 仍不启动
- 不建 `region_dict`；`order_address` 的省市区用 `VARCHAR` 文本快照
- 不改既有 64 个迁移文件与 `docs/spec/**`、`docs/prompt/MAIN.md`

## 3. 字段定义

### 3.1 来源标注规则

02 §2.5 只对 `order`、`order_item`、`order_amount_snapshot`、`order_status_log` 给出字段级要点，其余 8 张仅给表名。标注两列：

- **02 明示**：文档已写明的字段与约束，不得偏离
- **本 ST 提案**：按 §2.0 命名规范补齐的最小必要字段，**经用户确认后落地**；后续只能追加列，不能改名改语义

所有表均具备 `id UUID PRIMARY KEY`、`created_at`、`updated_at`、`deleted_at`（§2.0 通用列），`id` 由应用层生成 UUIDv7，DDL 不设默认值。

所有表**不建物理外键**（§2.0 第 3 条）：`user_id` / `merchant_id` / `shop_id` / `sku_id` / `order_id` 等引用由应用层校验 + 巡检保证，保证每张迁移可独立回滚。

金额 `NUMERIC(20,4)`；比率 `NUMERIC(10,6)`；币种 `CHAR(3)` 默认 `CNY`；数量 `INTEGER`；状态 `VARCHAR` + CHECK。

**`order` 是 PostgreSQL 保留字**：全部 SQL 必须写作 `"order"`（与既有 `"user"` 的处理一致），迁移文件名仍为 `order`。

`order_amount_snapshot`、`order_status_log`、`price_calc_log` 语义上「只增不改」，但仍保留 `deleted_at` 通用列（与 `audit_log`、`stock_log` 一致），由应用层保证不写软删。

### 3.2 `cart`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `item_count` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `total_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `status` | `VARCHAR(32)` | NOT NULL DEFAULT `'active'`，CHECK ∈ `active/merged/abandoned` | 本 ST 提案 |
| `last_active_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |

索引与约束：

- `uq_cart_user_id`：`UNIQUE (user_id) WHERE deleted_at IS NULL`——一个用户一条有效购物车
- `ck_cart_item_count`、`ck_cart_total_amount`、`ck_cart_status`

### 3.3 `cart_item`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `cart_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `merchant_id` / `shop_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `spu_id` / `sku_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 本 ST 提案 |
| `price_amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0`（加入时价格） | 本 ST 提案 |
| `selected` | `BOOLEAN` | NOT NULL DEFAULT `true` | 本 ST 提案 |
| `sku_snapshot` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 本 ST 提案 |

索引与约束：

- `uq_cart_item_cart_sku`：`UNIQUE (cart_id, sku_id) WHERE deleted_at IS NULL`——同车同 SKU 合并为一行
- `ix_cart_item_user_id`：`(user_id, updated_at DESC)`
- `ck_cart_item_qty`、`ck_cart_item_price_amount`

### 3.4 `"order"`（02 明示字段级）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NOT NULL，唯一（`SO+yyyymmdd+序列`） | 02 明示 |
| `user_id` / `merchant_id` / `shop_id` | `UUID` | NOT NULL | 02 明示 |
| `order_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'normal'`，CHECK ∈ `normal/presale/seckill/groupbuy/virtual/service` | 02 明示 |
| `status` | `VARCHAR(24)` | NOT NULL DEFAULT `'created'`，CHECK 见下 | 02 明示（长度 24） |
| `pay_status` | `VARCHAR(16)` | NOT NULL DEFAULT `'unpaid'`，CHECK ∈ `unpaid/paying/paid/refunding/refunded/closed` | 02 明示（子状态） |
| `ship_status` | `VARCHAR(16)` | NOT NULL DEFAULT `'unshipped'`，CHECK ∈ `unshipped/partial_shipped/shipped/received` | 02 明示（子状态） |
| `after_sale_status` | `VARCHAR(16)` | NOT NULL DEFAULT `'none'`，CHECK ∈ `none/applying/processing/finished` | 02 明示（子状态） |
| `currency` | `CHAR(3)` | NOT NULL DEFAULT `'CNY'` | 02 明示 |
| `goods_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `discount_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `freight_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `tax_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `payable_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `paid_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0` | 02 明示 |
| `snapshot_id` | `UUID` | NULL → `order_amount_snapshot` | 02 明示 |
| `channel` | `VARCHAR(16)` | NOT NULL DEFAULT `'web'`，CHECK ∈ `web/h5/miniapp/app/open/api` | 02 明示 |
| `source` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | 02 明示 |
| `parent_order_no` | `VARCHAR(32)` | NULL（拆单父单） | 02 明示 |
| `pay_expire_at` | `TIMESTAMPTZ` | NULL | 02 明示 |
| `auto_receive_at` | `TIMESTAMPTZ` | NULL | 02 明示 |

索引与约束：

- `uq_order_order_no`：`UNIQUE (order_no) WHERE deleted_at IS NULL`（**05 P1-2 点名的订单号唯一索引**）
- `ix_order_user_status_created`：`(user_id, status, created_at DESC)`（§2.15）
- `ix_order_merchant_status_created`：`(merchant_id, status, created_at DESC)`（§2.15）
- `ix_order_shop_status_created`：`(shop_id, status, created_at DESC)`（本 ST 提案，商家后台按店铺筛选）
- `ix_order_pay_expire`：`(pay_expire_at) WHERE status = 'pending_pay'`（§2.15，催付/超时关单扫描）
- `ix_order_parent_order_no`：`(parent_order_no)`（拆单反查）
- `ck_order_status`（10 个枚举：`created/pending_pay/paid/partially_shipped/shipped/received/after_sale/completed/cancelled/closed`）、`ck_order_order_type`、`ck_order_pay_status`、`ck_order_ship_status`、`ck_order_after_sale_status`、`ck_order_channel`
- `ck_order_amounts_non_negative`：六个金额列均 `>= 0`

> 02 明确「冗余汇总必须与快照一致（有校验任务）」，因此**不加** `payable = goods - discount + freight + tax` 这类数据库 CHECK：促销叠加下取整规则由计算引擎定义，硬编码会误杀合法订单。守恒校验放到 P9 巡检脚本。

### 3.5 `order_item`（02 明示）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_id` | `UUID` | NOT NULL | 本 ST 提案（便于关联） |
| `order_no` | `VARCHAR(32)` | NOT NULL | 02 明示 |
| `spu_id` / `sku_id` | `UUID` | NOT NULL | 02 明示 |
| `sku_snapshot` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb`（下单时商品关键属性快照） | 02 明示 |
| `qty` | `INTEGER` | NOT NULL，CHECK `> 0` | 02 明示 |
| `unit_price` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 02 明示 |
| `item_amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 02 明示 |
| `discount_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `tax_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `refund_qty` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND refund_qty <= qty` | 02 明示 |
| `refund_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 02 明示 |
| `after_sale_status` | `VARCHAR(16)` | NOT NULL DEFAULT `'none'`，CHECK ∈ `none/applying/processing/finished` | 02 明示 |

索引与约束：

- `ix_order_item_order_id`：`(order_id)`
- `ix_order_item_order_no`：`(order_no)`
- `ix_order_item_sku_id`：`(sku_id, created_at DESC)`
- `ck_order_item_qty`、`ck_order_item_amounts`、`ck_order_item_refund_qty`、`ck_order_item_after_sale_status`

> **不加** `(order_id, sku_id)` 唯一索引：同一 SKU 可能因不同活动/赠品拆成多行，02 未要求唯一。

### 3.6 `order_amount_snapshot`（02 明示，只增不改）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NOT NULL | 02 明示 |
| `calc_version` | `VARCHAR(32)` | NOT NULL | 02 明示 |
| `input` | `JSONB` | NOT NULL（用户、券包、活动、地址） | 02 明示 |
| `output` | `JSONB` | NOT NULL（逐 SKU 分摊明细） | 02 明示 |

索引与约束：

- `uq_order_amount_snapshot_order_no`：`UNIQUE (order_no) WHERE deleted_at IS NULL`（02 明示「`order_no` 唯一」）

### 3.7 `order_address`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `address_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'shipping'`，CHECK ∈ `shipping/return` | 本 ST 提案 |
| `receiver_name` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `receiver_phone_enc` | `TEXT` | NOT NULL（加密存储） | 本 ST 提案 |
| `province` / `city` / `district` | `VARCHAR(64)` | NOT NULL | 本 ST 提案 |
| `detail_address` | `VARCHAR(255)` | NOT NULL | 本 ST 提案 |
| `postal_code` | `VARCHAR(16)` | NULL | 本 ST 提案 |

索引与约束：

- `uq_order_address_order_type`：`UNIQUE (order_no, address_type) WHERE deleted_at IS NULL`——每单每种地址一份快照
- `ck_order_address_type`

### 3.8 `order_status_log`（02 明示，只增不改）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `order_no` | `VARCHAR(32)` | NOT NULL | 02 明示 |
| `from_status` | `VARCHAR(24)` | NULL（首条无前态） | 02 明示 |
| `to_status` | `VARCHAR(24)` | NOT NULL | 02 明示 |
| `action` | `VARCHAR(32)` | NOT NULL | 02 明示 |
| `operator_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'system'`，CHECK ∈ `user/merchant/platform/system` | 02 明示 |
| `operator_id` | `UUID` | NULL | 02 明示 |
| `reason` | `VARCHAR(255)` | NULL | 02 明示 |
| `trace_id` | `VARCHAR(64)` | NULL | 02 明示 |

索引与约束：

- `ix_order_status_log_order_no_created`：`(order_no, created_at)`
- `ix_order_status_log_trace_id`：`(trace_id)`
- `ck_order_status_log_operator_type`

> 02 §2.15 将 `order_status_log` 列入「按月分区」清单。本批是否分区见 §7 决策点 2（与 ST-1.5 的 `stock_log` 决策保持一致）。

### 3.9 `order_remark`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `remark_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'user'`，CHECK ∈ `user/merchant/platform` | 本 ST 提案 |
| `content` | `TEXT` | NOT NULL | 本 ST 提案 |
| `operator_id` | `UUID` | NULL | 本 ST 提案 |
| `is_pinned` | `BOOLEAN` | NOT NULL DEFAULT `false` | 本 ST 提案 |

索引与约束：

- `ix_order_remark_order_no`：`(order_no, created_at DESC)`
- `ck_order_remark_type`

### 3.10 `order_tag`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `tag_code` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `tag_name` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `source` | `VARCHAR(16)` | NOT NULL DEFAULT `'manual'`，CHECK ∈ `manual/rule/ai` | 本 ST 提案 |

索引与约束：

- `uq_order_tag_order_tag`：`UNIQUE (order_no, tag_code) WHERE deleted_at IS NULL`
- `ix_order_tag_tag_code`：`(tag_code, created_at DESC)`
- `ck_order_tag_source`

### 3.11 `invoice`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `invoice_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `order_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `invoice_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'personal'`，CHECK ∈ `personal/company` | 本 ST 提案 |
| `title` | `VARCHAR(128)` | NOT NULL | 本 ST 提案 |
| `tax_no` | `VARCHAR(64)` | NULL | 本 ST 提案 |
| `amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 本 ST 提案 |
| `status` | `VARCHAR(16)` | NOT NULL DEFAULT `'applied'`，CHECK ∈ `applied/issued/failed/void` | 本 ST 提案 |
| `invoice_code` | `VARCHAR(32)` | NULL（税控返回） | 本 ST 提案 |
| `invoice_number` | `VARCHAR(32)` | NULL（税控返回） | 本 ST 提案 |
| `issued_at` | `TIMESTAMPTZ` | NULL | 本 ST 提案 |
| `file_url` | `TEXT` | NULL | 本 ST 提案 |

索引与约束：

- `uq_invoice_invoice_no`：`UNIQUE (invoice_no) WHERE deleted_at IS NULL`
- `ix_invoice_order_no`：`(order_no)`
- `ix_invoice_user_status`：`(user_id, status, created_at DESC)`
- `ck_invoice_type`、`ck_invoice_status`、`ck_invoice_amount`

> 同一订单允许多次开票记录（作废后重开），故 `order_no` 不设唯一索引。

### 3.12 `invoice_item`

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `invoice_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `order_no` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `order_item_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `name` | `VARCHAR(255)` | NOT NULL | 本 ST 提案 |
| `amount` | `NUMERIC(20,4)` | NOT NULL，CHECK `>= 0` | 本 ST 提案 |
| `tax_rate` | `NUMERIC(10,6)` | NOT NULL DEFAULT `0`，CHECK `>= 0 AND tax_rate <= 1` | 本 ST 提案 |
| `tax_amount` | `NUMERIC(20,4)` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |

索引与约束：

- `uq_invoice_item_invoice_order_item`：`UNIQUE (invoice_id, order_item_id) WHERE deleted_at IS NULL`
- `ck_invoice_item_amount`、`ck_invoice_item_tax_rate`

### 3.13 `price_calc_log`（计算留痕，只增不改）

| 列 | 类型 | 约束 | 来源 |
|---|---|---|---|
| `order_no` | `VARCHAR(32)` | NULL（预览阶段可能无单号） | 本 ST 提案 |
| `user_id` | `UUID` | NOT NULL | 本 ST 提案 |
| `calc_type` | `VARCHAR(16)` | NOT NULL DEFAULT `'order'`，CHECK ∈ `cart/order/preview` | 本 ST 提案 |
| `engine_version` | `VARCHAR(32)` | NOT NULL | 本 ST 提案 |
| `input` | `JSONB` | NOT NULL | 本 ST 提案 |
| `output` | `JSONB` | NOT NULL | 本 ST 提案 |
| `duration_ms` | `INTEGER` | NOT NULL DEFAULT `0`，CHECK `>= 0` | 本 ST 提案 |
| `trace_id` | `VARCHAR(64)` | NULL | 本 ST 提案 |

索引与约束：

- `ix_price_calc_log_order_no`：`(order_no) WHERE order_no IS NOT NULL`
- `ix_price_calc_log_user_created`：`(user_id, created_at DESC)`
- `ck_price_calc_log_type`、`ck_price_calc_log_duration`

## 4. 迁移与种子设计

### 4.1 迁移命名

沿用 ADR-002 时间戳前缀，接在 `20261125116000` 之后，一表一迁移：

| 序号 | 版本前缀 | 主题 |
|---|---|---|
| 1 | `20261125116100` | `cart` |
| 2 | `20261125116200` | `cart_item` |
| 3 | `20261125116300` | `order` |
| 4 | `20261125116400` | `order_item` |
| 5 | `20261125116500` | `order_amount_snapshot` |
| 6 | `20261125116600` | `order_address` |
| 7 | `20261125116700` | `order_status_log` |
| 8 | `20261125116800` | `order_remark` |
| 9 | `20261125116900` | `order_tag` |
| 10 | `20261125117000` | `invoice` |
| 11 | `20261125117100` | `invoice_item` |
| 12 | `20261125117200` | `price_calc_log` |

`down.sql` 只 `DROP TABLE IF EXISTS` 本表（`order` 写作 `DROP TABLE IF EXISTS "order"`），保证可从最新版本逐条回滚到 `20261125116000` 而互不牵连。

### 4.2 约束命名汇总（供断言脚本使用）

- 软删部分唯一索引 8 组：`uq_cart_user_id`、`uq_cart_item_cart_sku`、`uq_order_order_no`、`uq_order_amount_snapshot_order_no`、`uq_order_address_order_type`、`uq_order_tag_order_tag`、`uq_invoice_invoice_no`、`uq_invoice_item_invoice_order_item`
- 部分普通索引 1 组：`ix_order_pay_expire`（`WHERE status = 'pending_pay'`，非唯一）
- 05 P1-2 点名：`uq_order_order_no`（订单号唯一）
- 关键 CHECK：`ck_order_status`、`ck_order_order_type`、`ck_order_pay_status`、`ck_order_ship_status`、`ck_order_after_sale_status`、`ck_order_channel`、`ck_order_amounts_non_negative`、`ck_order_item_qty`、`ck_order_item_refund_qty`、`ck_cart_item_qty`、`ck_invoice_amount`、`ck_invoice_item_tax_rate`

### 4.3 种子（待确认）

`scripts/seed_trade_demo.sql`，非迁移、可重复执行、单事务、主键确定性 UUID（`01930000-0000-7000-8000-` + 序号）、全部 `ON CONFLICT DO NOTHING`。具体范围见 §7 决策点 4；依赖 ST-1.3 demo 商家/店铺与 ST-1.4 的 `SKU_DEMO_0001/0002`，缺失时自动插入 0 行，不产生孤儿数据。

## 5. 验证

### 5.1 迁移可执行、可独立回滚（05 P1-1）

在空库 `ecom_p1_trade` 上执行：

```powershell
sqlx migrate run
sqlx migrate revert   # 依次回滚 price_calc_log → ... → cart
sqlx migrate run
```

断言：每次 `revert` 后仅目标表消失；前五批 64 张表始终存在；再次 `run` 后 76 张表全部恢复。

### 5.2 约束断言（05 P1-2 的交易部分）

在 `scripts/verify_p1_constraints.sql` 追加第六段：

1. 12 张表存在（`order` 用 `quote_ident` 生成 `"order"`）
2. 8 组软删部分唯一索引唯一且带 `WHERE deleted_at IS NULL`，**含 05 点名的 `uq_order_order_no`**
3. 索引列序：`ix_order_user_status_created` = `(user_id, status, created_at)`、`ix_order_merchant_status_created` = `(merchant_id, status, created_at)`、`ix_order_pay_expire` 带 `WHERE status = 'pending_pay'`
4. 关键 CHECK 存在，且非法写入被拒绝：
   - `"order".status` 非法、`order_type` 非法、`channel` 非法
   - `"order".goods_amount = -1`
   - `order_item.qty = 0`、`refund_qty > qty`
   - `cart_item.qty = 0`
   - `invoice.amount = -1`、`invoice_item.tax_rate = 1.5`
   - `order_address.address_type` 非法
5. 重复写入拒绝：
   - 同一 `order_no` 两条 `"order"` 被 `uq_order_order_no` 拒绝
   - 同一 `(cart_id, sku_id)` 两条 `cart_item` 被拒绝
   - 同一 `order_no` 两条 `order_amount_snapshot` 被拒绝
   - 同一订单两个 `shipping` 地址被拒绝
6. 精度：`"order".goods_amount` = `NUMERIC(20,4)`、`invoice_item.tax_rate` = `NUMERIC(10,6)`

### 5.3 种子幂等

```powershell
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_trade_demo.sql   # 第一次
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_trade_demo.sql   # 第二次
```

断言：涉及表行数两次一致，`order_no` 哈希一致。

### 5.4 状态机单测（05 P1-4 的本批部分）

`crates/domain/src/trade.rs` 订单状态机一组测试：

1. 合法迁移全过：逐条断言 `(from, action) -> Ok(to)`
2. 非法迁移全错：遍历「全部状态 × 全部动作」矩阵
3. 覆盖 02 §2.13① 的关键约束：`pending_pay` 才可 `pay_success`；`after_sale` 不再接受发货/收货；终态（`cancelled/completed/closed`）不接受 `force_close`

### 5.5 回归

- `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace` 退出码 0
- `git diff --check` 退出码 0；`git status --short` 全部落在白名单内

## 6. 文件白名单

新增：

- `specs/ST-1.6.md`
- `migrations/20261125116100`~`20261125117200` 共 12 组 `{up,down}.sql`
- `scripts/seed_trade_demo.sql`
- `crates/domain/src/trade.rs`（订单状态机 + 单测）

修改：

- `scripts/verify_p1_constraints.sql`（追加交易域断言段，保留前五段不变）
- `docs/gates/P1.md`（追加 ST-1.6 证据）
- `crates/domain/src/lib.rs`（`pub mod trade;`）

明确不改：`apps/**`、`crates/**` 中除 `domain` 外的部分、`Cargo.toml` / `Cargo.lock`（`thiserror` 已在 ST-1.5 引入）、`deploy/**`、`docs/adr/**`、`docs/spec/**`、`docs/prompt/MAIN.md`、`docs/tech-debt.md`、`docs/gates/P0.md`、既有 64 个迁移。

## 7. 已确认的决策点

用户已确认：

1. **批次范围**：02 §2.5 明列的 **12 张一次交付**（购物车 2 + 订单主链 6 + 票据/留痕 4）。
2. **`order_status_log` 分区**：本批建**普通表**，按月分区随 P4 并发压测统一改造（与 ST-1.5 `stock_log` 的决策一致）。
3. **订单状态机口径**：严格照 02 §2.13① 表格实现，`after_sale --after_sale_done--> completed`；不补 `partially_shipped` 继续发货箭头。两处偏差写入 `trade.rs` 注释与本 spec。
4. **种子范围**：新增 1 个 demo 用户 + 1 条购物车（2 条明细）+ 1 笔已支付订单全链（2 条明细、金额快照、收货地址、3 条状态日志、备注、标签）。

## 8. 完成定义

- 12 条迁移在空库 up 成功，可逐条 down 干净回滚并再次 up 成功，有真实输出
- `scripts/verify_p1_constraints.sql` 两次执行均 0 错误，前五段仍通过；`uq_order_order_no` 断言通过
- 交易域种子连续两次执行结果一致（若确认落地）
- 订单状态机单测全绿：合法迁移全过、非法组合全错
- `docs/gates/P1.md` 记录命令、退出码与断言结论，并更新 P1-1/P1-2/P1-3/P1-4 进度
- 三条 Rust 门禁仍全绿，无白名单外改动
- P1-5 如实保持 ⬜（仍缺分账/结算表），不提前声称完成
