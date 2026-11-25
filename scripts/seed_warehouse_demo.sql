-- ST-1.5 库存与供应链演示种子：可重复执行（ON CONFLICT DO NOTHING），单事务。
-- 依赖 ST-1.3 的 demo 商家与 ST-1.4 的 20 个示例 SKU；缺失时对应步骤插入 0 行，不产生孤儿数据。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_warehouse_demo.sql
BEGIN;

SET LOCAL statement_timeout = '30s';

-- 1. 演示仓库（每商家一个默认仓）
INSERT INTO warehouse (
    id, warehouse_no, merchant_id, name, type, province, city, district, address,
    contact_name, contact_phone, is_default, sort_weight, status
)
SELECT
    '01930000-0000-7000-8000-000000000901'::uuid,
    'W_DEMO_0001',
    m.id,
    '演示华东仓',
    'normal',
    '浙江省',
    '杭州市',
    '余杭区',
    '演示路 1 号',
    '演示仓管',
    '13800000001',
    true,
    0,
    'active'
FROM merchant m
WHERE m.merchant_no = 'M_DEMO_0001' AND m.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 2. 演示库区（配送区域不限）
INSERT INTO warehouse_zone (id, warehouse_id, zone_no, name, region_codes, priority, status)
SELECT
    '01930000-0000-7000-8000-000000000902'::uuid,
    w.id,
    'Z_DEMO_0001',
    '默认库区',
    '[]'::jsonb,
    0,
    'active'
FROM warehouse w
WHERE w.warehouse_no = 'W_DEMO_0001' AND w.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 3. 20 个示例 SKU 的初始库存（available 1000 / safety 50）
INSERT INTO sku_stock (id, sku_id, warehouse_id, available_qty, locked_qty, occupied_qty, safety_qty, version)
SELECT
    ('01930000-0000-7000-8000-' || lpad((920 + i)::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((720 + i)::text, 12, '0'))::uuid,
    w.id,
    1000,
    0,
    0,
    50,
    0
FROM generate_series(1, 20) AS i
JOIN sku s ON s.id = ('01930000-0000-7000-8000-' || lpad((720 + i)::text, 12, '0'))::uuid
          AND s.deleted_at IS NULL
CROSS JOIN LATERAL (
    SELECT id FROM warehouse WHERE warehouse_no = 'W_DEMO_0001' AND deleted_at IS NULL LIMIT 1
) AS w
ON CONFLICT DO NOTHING;

COMMIT;
