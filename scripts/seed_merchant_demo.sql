-- ST-1.3 商家域演示种子：可重复执行（ON CONFLICT DO NOTHING），单事务。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_merchant_demo.sql
BEGIN;

SET LOCAL statement_timeout = '30s';

-- 1. 演示商家
INSERT INTO merchant (
    id, merchant_no, name, type, status, commission_rate, settle_cycle,
    contact_name, applied_at, activated_at
)
VALUES (
    '01930000-0000-7000-8000-000000000301'::uuid,
    'M_DEMO_0001',
    '演示商家有限公司',
    'company',
    'active',
    0.050000,
    'T+1',
    '演示联系人',
    now(),
    now()
)
ON CONFLICT DO NOTHING;

-- 2. 演示店铺（挂在该商家下）
INSERT INTO shop (id, merchant_id, shop_no, name, intro, status)
SELECT
    '01930000-0000-7000-8000-000000000302'::uuid,
    m.id,
    'S_DEMO_0001',
    '演示旗舰店',
    '用于本地开发与联调的演示店铺',
    'active'
FROM merchant m
WHERE m.merchant_no = 'M_DEMO_0001' AND m.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 3. 演示保证金账户
INSERT INTO deposit_account (id, merchant_id, balance_amount, frozen_amount, currency)
SELECT
    '01930000-0000-7000-8000-000000000303'::uuid,
    m.id,
    10000.0000,
    0,
    'CNY'
FROM merchant m
WHERE m.merchant_no = 'M_DEMO_0001' AND m.deleted_at IS NULL
ON CONFLICT DO NOTHING;

COMMIT;
