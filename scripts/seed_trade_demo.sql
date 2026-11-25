-- ST-1.6 交易域种子：demo 用户 / 购物车 / 一笔已支付订单全链。
-- 可重复执行（确定性主键 + ON CONFLICT DO NOTHING），单事务。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_trade_demo.sql
-- 说明：订单依赖 ST-1.3 demo 店铺与 ST-1.4 的 SKU_DEMO_0001/0002；缺失时自动插入 0 行，不产生孤儿数据。
BEGIN;

SET LOCAL statement_timeout = '60s';

-- 1. demo 用户（当前库无任何 user 种子）
INSERT INTO "user" (id, phone_hash, phone_enc, nickname, status, realname_status, points_balance)
VALUES (
    '01930000-0000-7000-8000-000000001001'::uuid,
    'demo-phone-hash-0001',
    'demo-phone-enc-0001',
    '演示用户',
    'active',
    'unverified',
    0
)
ON CONFLICT DO NOTHING;

-- 2. 购物车（数量与金额在第 4 步按实际明细回写）
INSERT INTO cart (id, user_id, item_count, total_amount, status, last_active_at)
VALUES (
    '01930000-0000-7000-8000-000000001101'::uuid,
    '01930000-0000-7000-8000-000000001001'::uuid,
    0,
    0,
    'active',
    now()
)
ON CONFLICT DO NOTHING;

-- 3. 购物车明细：SKU_DEMO_0001 / SKU_DEMO_0002，各 1 件
INSERT INTO cart_item (id, cart_id, user_id, merchant_id, shop_id, spu_id, sku_id, qty, price_amount, selected, sku_snapshot)
SELECT
    ('01930000-0000-7000-8000-' || lpad((1110 + i)::text, 12, '0'))::uuid,
    '01930000-0000-7000-8000-000000001101'::uuid,
    '01930000-0000-7000-8000-000000001001'::uuid,
    p.merchant_id,
    p.shop_id,
    p.id,
    s.id,
    1,
    (100 + i * 50)::numeric(20,4),
    true,
    '{"颜色":"默认"}'::jsonb
FROM generate_series(1, 2) AS i
JOIN sku s ON s.sku_no = 'SKU_DEMO_' || lpad(i::text, 4, '0') AND s.deleted_at IS NULL
JOIN spu p ON p.id = s.spu_id AND p.deleted_at IS NULL
WHERE EXISTS (
    SELECT 1 FROM cart WHERE id = '01930000-0000-7000-8000-000000001101'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 4. 回写购物车汇总（无明细时为 0）
UPDATE cart
SET item_count = (
        SELECT COALESCE(sum(ci.qty), 0) FROM cart_item ci
        WHERE ci.cart_id = cart.id AND ci.deleted_at IS NULL
    ),
    total_amount = (
        SELECT COALESCE(sum(ci.price_amount * ci.qty), 0) FROM cart_item ci
        WHERE ci.cart_id = cart.id AND ci.deleted_at IS NULL
    ),
    updated_at = now()
WHERE id = '01930000-0000-7000-8000-000000001101'::uuid;

-- 5. 已支付订单主表（依赖 demo 店铺）
INSERT INTO "order" (
    id, order_no, user_id, merchant_id, shop_id, order_type, status,
    pay_status, ship_status, after_sale_status, currency,
    goods_amount, discount_amount, freight_amount, tax_amount, payable_amount, paid_amount,
    snapshot_id, channel, source, pay_expire_at
)
SELECT
    '01930000-0000-7000-8000-000000001121'::uuid,
    'SO20261125000001',
    '01930000-0000-7000-8000-000000001001'::uuid,
    sh.merchant_id,
    sh.id,
    'normal',
    'paid',
    'paid',
    'unshipped',
    'none',
    'CNY',
    350,
    0,
    0,
    0,
    350,
    350,
    '01930000-0000-7000-8000-000000001141'::uuid,
    'web',
    '{"scene":"demo"}'::jsonb,
    now() + interval '30 minutes'
FROM shop sh
WHERE sh.shop_no = 'S_DEMO_0001'
  AND sh.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 6. 订单明细：两行，各 1 件
INSERT INTO order_item (
    id, order_id, order_no, spu_id, sku_id, sku_snapshot, qty,
    unit_price, item_amount, discount_amount, tax_amount, refund_qty, refund_amount, after_sale_status
)
SELECT
    ('01930000-0000-7000-8000-' || lpad((1130 + i)::text, 12, '0'))::uuid,
    '01930000-0000-7000-8000-000000001121'::uuid,
    'SO20261125000001',
    s.spu_id,
    s.id,
    '{"颜色":"默认"}'::jsonb,
    1,
    (100 + i * 50)::numeric(20,4),
    (100 + i * 50)::numeric(20,4),
    0,
    0,
    0,
    0,
    'none'
FROM generate_series(1, 2) AS i
JOIN sku s ON s.sku_no = 'SKU_DEMO_' || lpad(i::text, 4, '0') AND s.deleted_at IS NULL
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 7. 金额计算快照（只增不改）
INSERT INTO order_amount_snapshot (id, order_no, calc_version, input, output)
SELECT
    '01930000-0000-7000-8000-000000001141'::uuid,
    'SO20261125000001',
    'v1',
    '{"user_id":"01930000-0000-7000-8000-000000001001","coupon_ids":[],"promotion_ids":[]}'::jsonb,
    '{"goods_amount":350.0000,"discount_amount":0,"freight_amount":0,"tax_amount":0,"payable_amount":350.0000}'::jsonb
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 8. 收货地址快照
INSERT INTO order_address (
    id, order_no, address_type, receiver_name, receiver_phone_enc,
    province, city, district, detail_address, postal_code
)
SELECT
    '01930000-0000-7000-8000-000000001151'::uuid,
    'SO20261125000001',
    'shipping',
    '张演示',
    'demo-phone-enc-0001',
    '浙江省',
    '杭州市',
    '西湖区',
    '文三路 100 号',
    '310000'
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 9. 订单状态日志：created → pending_pay → paid
INSERT INTO order_status_log (id, order_id, order_no, from_status, to_status, action, operator_type, operator_id, reason)
SELECT
    ('01930000-0000-7000-8000-' || lpad((1160 + i)::text, 12, '0'))::uuid,
    '01930000-0000-7000-8000-000000001121'::uuid,
    'SO20261125000001',
    CASE i WHEN 1 THEN NULL WHEN 2 THEN 'created' ELSE 'pending_pay' END,
    CASE i WHEN 1 THEN 'created' WHEN 2 THEN 'pending_pay' ELSE 'paid' END,
    CASE i WHEN 1 THEN 'create' WHEN 2 THEN 'reserve_ok' ELSE 'pay_success' END,
    'system',
    NULL,
    '演示订单链路'
FROM generate_series(1, 3) AS i
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 10. 订单备注
INSERT INTO order_remark (id, order_no, remark_type, content, operator_id, is_pinned)
SELECT
    '01930000-0000-7000-8000-000000001171'::uuid,
    'SO20261125000001',
    'user',
    '演示订单备注：请尽快发货',
    '01930000-0000-7000-8000-000000001001'::uuid,
    true
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 11. 订单标签
INSERT INTO order_tag (id, order_no, tag_code, tag_name, source)
SELECT
    '01930000-0000-7000-8000-000000001181'::uuid,
    'SO20261125000001',
    'demo',
    '演示标签',
    'manual'
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 12. 发票
INSERT INTO invoice (
    id, invoice_no, order_no, user_id, invoice_type, title, amount, status, issued_at
)
SELECT
    '01930000-0000-7000-8000-000000001191'::uuid,
    'INV20261125000001',
    'SO20261125000001',
    '01930000-0000-7000-8000-000000001001'::uuid,
    'personal',
    '演示用户',
    350,
    'issued',
    now()
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 13. 发票明细：按订单明细逐行
INSERT INTO invoice_item (id, invoice_id, order_no, order_item_id, name, amount, tax_rate, tax_amount)
SELECT
    ('01930000-0000-7000-8000-' || lpad((1200 + i)::text, 12, '0'))::uuid,
    '01930000-0000-7000-8000-000000001191'::uuid,
    'SO20261125000001',
    ('01930000-0000-7000-8000-' || lpad((1130 + i)::text, 12, '0'))::uuid,
    '演示商品 ' || lpad(i::text, 2, '0'),
    (100 + i * 50)::numeric(20,4),
    0.130000,
    ((100 + i * 50) * 0.13)::numeric(20,4)
FROM generate_series(1, 2) AS i
WHERE EXISTS (
    SELECT 1 FROM invoice WHERE id = '01930000-0000-7000-8000-000000001191'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

-- 14. 价格计算留痕
INSERT INTO price_calc_log (id, order_no, user_id, calc_type, engine_version, input, output, duration_ms, trace_id)
SELECT
    '01930000-0000-7000-8000-000000001211'::uuid,
    'SO20261125000001',
    '01930000-0000-7000-8000-000000001001'::uuid,
    'order',
    'v1',
    '{"items":2,"has_coupon":false}'::jsonb,
    '{"payable_amount":350.0000}'::jsonb,
    12,
    'demo-trace-0001'
WHERE EXISTS (
    SELECT 1 FROM "order" WHERE id = '01930000-0000-7000-8000-000000001121'::uuid AND deleted_at IS NULL
)
ON CONFLICT DO NOTHING;

COMMIT;
