-- ST-1.4 商品域种子：类目树 / 品牌 / 属性模板 / 20 个示例商品。
-- 可重复执行（ON CONFLICT DO NOTHING），单事务。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_product_dict.sql
-- 说明：示例商品依赖 ST-1.3 的 demo 商家/店铺；若不存在则商品部分自动插入 0 行，字典部分不受影响。
BEGIN;

SET LOCAL statement_timeout = '60s';

-- 1. 一级类目
INSERT INTO category (id, code, name, level, path, is_leaf, sort_weight, status) VALUES
    ('01930000-0000-7000-8000-000000000601'::uuid, 'DIGITAL', '数码', 1, '/01930000-0000-7000-8000-000000000601/', false, 1, 'active'),
    ('01930000-0000-7000-8000-000000000602'::uuid, 'APPAREL', '服饰', 1, '/01930000-0000-7000-8000-000000000602/', false, 2, 'active'),
    ('01930000-0000-7000-8000-000000000603'::uuid, 'FOOD', '食品', 1, '/01930000-0000-7000-8000-000000000603/', false, 3, 'active')
ON CONFLICT DO NOTHING;

-- 2. 二级类目
INSERT INTO category (id, parent_id, code, name, level, path, is_leaf, sort_weight, status) VALUES
    ('01930000-0000-7000-8000-000000000604'::uuid, '01930000-0000-7000-8000-000000000601'::uuid, 'MOBILE', '手机数码', 2, '/01930000-0000-7000-8000-000000000601/01930000-0000-7000-8000-000000000604/', true, 1, 'active'),
    ('01930000-0000-7000-8000-000000000605'::uuid, '01930000-0000-7000-8000-000000000601'::uuid, 'COMPUTER', '电脑办公', 2, '/01930000-0000-7000-8000-000000000601/01930000-0000-7000-8000-000000000605/', true, 2, 'active'),
    ('01930000-0000-7000-8000-000000000606'::uuid, '01930000-0000-7000-8000-000000000602'::uuid, 'MENSWEAR', '男装', 2, '/01930000-0000-7000-8000-000000000602/01930000-0000-7000-8000-000000000606/', true, 1, 'active'),
    ('01930000-0000-7000-8000-000000000607'::uuid, '01930000-0000-7000-8000-000000000602'::uuid, 'WOMENSWEAR', '女装', 2, '/01930000-0000-7000-8000-000000000602/01930000-0000-7000-8000-000000000607/', true, 2, 'active'),
    ('01930000-0000-7000-8000-000000000608'::uuid, '01930000-0000-7000-8000-000000000603'::uuid, 'SNACK', '零食', 2, '/01930000-0000-7000-8000-000000000603/01930000-0000-7000-8000-000000000608/', true, 1, 'active'),
    ('01930000-0000-7000-8000-000000000609'::uuid, '01930000-0000-7000-8000-000000000603'::uuid, 'GRAIN', '粮油', 2, '/01930000-0000-7000-8000-000000000603/01930000-0000-7000-8000-000000000609/', true, 2, 'active')
ON CONFLICT DO NOTHING;

-- 3. 品牌
INSERT INTO brand (id, name, name_en, first_letter, description, sort_weight, status) VALUES
    ('01930000-0000-7000-8000-000000000611'::uuid, '华为', 'HUAWEI', 'H', '演示品牌', 1, 'active'),
    ('01930000-0000-7000-8000-000000000612'::uuid, '小米', 'XIAOMI', 'X', '演示品牌', 2, 'active'),
    ('01930000-0000-7000-8000-000000000613'::uuid, '苹果', 'APPLE', 'P', '演示品牌', 3, 'active'),
    ('01930000-0000-7000-8000-000000000614'::uuid, '李宁', 'LI-NING', 'L', '演示品牌', 4, 'active'),
    ('01930000-0000-7000-8000-000000000615'::uuid, '三只松鼠', 'THREE SQUIRRELS', 'S', '演示品牌', 5, 'active')
ON CONFLICT DO NOTHING;

-- 4. 类目属性模板
INSERT INTO category_attr (id, category_id, code, name, attr_type, input_type, is_required, is_sku_attr, is_searchable, is_filterable, unit, sort_weight, status) VALUES
    ('01930000-0000-7000-8000-000000000621'::uuid, '01930000-0000-7000-8000-000000000601'::uuid, 'brand', '品牌', 'sale', 'select', true, false, true, true, NULL, 1, 'active'),
    ('01930000-0000-7000-8000-000000000622'::uuid, '01930000-0000-7000-8000-000000000601'::uuid, 'warranty_month', '保修期', 'sale', 'number', false, false, false, true, '月', 2, 'active'),
    ('01930000-0000-7000-8000-000000000623'::uuid, '01930000-0000-7000-8000-000000000601'::uuid, 'origin', '产地', 'prop', 'text', false, false, true, false, NULL, 3, 'active'),
    ('01930000-0000-7000-8000-000000000624'::uuid, '01930000-0000-7000-8000-000000000602'::uuid, 'material', '材质', 'sale', 'text', false, false, true, true, NULL, 1, 'active'),
    ('01930000-0000-7000-8000-000000000625'::uuid, '01930000-0000-7000-8000-000000000602'::uuid, 'size', '尺码', 'sale', 'multi_select', true, true, true, true, NULL, 2, 'active'),
    ('01930000-0000-7000-8000-000000000626'::uuid, '01930000-0000-7000-8000-000000000602'::uuid, 'origin', '产地', 'prop', 'text', false, false, true, false, NULL, 3, 'active'),
    ('01930000-0000-7000-8000-000000000627'::uuid, '01930000-0000-7000-8000-000000000603'::uuid, 'shelf_life_day', '保质期', 'sale', 'number', true, false, false, true, '天', 1, 'active'),
    ('01930000-0000-7000-8000-000000000628'::uuid, '01930000-0000-7000-8000-000000000603'::uuid, 'origin', '产地', 'prop', 'text', false, false, true, false, NULL, 2, 'active'),
    ('01930000-0000-7000-8000-000000000629'::uuid, '01930000-0000-7000-8000-000000000603'::uuid, 'package', '包装', 'sale', 'select', false, false, false, true, NULL, 3, 'active')
ON CONFLICT DO NOTHING;

-- 5. 属性可选值
INSERT INTO category_attr_value (id, attr_id, value, sort_weight, status) VALUES
    ('01930000-0000-7000-8000-000000000641'::uuid, '01930000-0000-7000-8000-000000000621'::uuid, '华为', 1, 'active'),
    ('01930000-0000-7000-8000-000000000642'::uuid, '01930000-0000-7000-8000-000000000621'::uuid, '小米', 2, 'active'),
    ('01930000-0000-7000-8000-000000000643'::uuid, '01930000-0000-7000-8000-000000000621'::uuid, '苹果', 3, 'active'),
    ('01930000-0000-7000-8000-000000000644'::uuid, '01930000-0000-7000-8000-000000000625'::uuid, 'S', 1, 'active'),
    ('01930000-0000-7000-8000-000000000645'::uuid, '01930000-0000-7000-8000-000000000625'::uuid, 'M', 2, 'active'),
    ('01930000-0000-7000-8000-000000000646'::uuid, '01930000-0000-7000-8000-000000000625'::uuid, 'L', 3, 'active'),
    ('01930000-0000-7000-8000-000000000647'::uuid, '01930000-0000-7000-8000-000000000629'::uuid, '袋装', 1, 'active'),
    ('01930000-0000-7000-8000-000000000648'::uuid, '01930000-0000-7000-8000-000000000629'::uuid, '盒装', 2, 'active')
ON CONFLICT DO NOTHING;

-- 6. 20 个示例 SPU（依赖 demo 商家/店铺，缺失时插入 0 行）
INSERT INTO spu (
    id, spu_no, merchant_id, shop_id, category_id, brand_id, title, sub_title,
    main_image, status, audit_status, is_self_support, sort_weight, published_at
)
SELECT
    ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid,
    'SPU_DEMO_' || lpad(i::text, 4, '0'),
    d.merchant_id,
    d.shop_id,
    ('01930000-0000-7000-8000-' || lpad((604 + ((i - 1) % 6))::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((611 + ((i - 1) % 5))::text, 12, '0'))::uuid,
    '演示商品 ' || lpad(i::text, 2, '0'),
    '用于本地开发与联调的示例 SPU',
    '/static/demo/spu/' || lpad(i::text, 4, '0') || '.jpg',
    'on_sale',
    'approved',
    false,
    0,
    now()
FROM generate_series(1, 20) AS i
CROSS JOIN LATERAL (
    SELECT m.id AS merchant_id, s.id AS shop_id
    FROM merchant m
    JOIN shop s ON s.merchant_id = m.id
    WHERE m.merchant_no = 'M_DEMO_0001'
      AND s.shop_no = 'S_DEMO_0001'
      AND m.deleted_at IS NULL
      AND s.deleted_at IS NULL
    LIMIT 1
) AS d
ON CONFLICT DO NOTHING;

-- 7. 每个示例 SPU 一个 SKU
INSERT INTO sku (id, sku_no, spu_id, barcode, spec_values, image, weight_g, volume_cm3, status, version)
SELECT
    ('01930000-0000-7000-8000-' || lpad((720 + i)::text, 12, '0'))::uuid,
    'SKU_DEMO_' || lpad(i::text, 4, '0'),
    ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid,
    '690000000' || lpad(i::text, 4, '0'),
    '{"颜色":"默认"}'::jsonb,
    '/static/demo/sku/' || lpad(i::text, 4, '0') || '.jpg',
    500,
    1000,
    'on_sale',
    0
FROM generate_series(1, 20) AS i
JOIN spu ON spu.id = ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid
        AND spu.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 8. 每个 SKU 一条销售价
INSERT INTO sku_price (id, sku_id, price_type, price_amount, min_qty, currency, status)
SELECT
    ('01930000-0000-7000-8000-' || lpad((740 + i)::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((720 + i)::text, 12, '0'))::uuid,
    'sale',
    (100 + i * 50)::numeric(20,4),
    1,
    'CNY',
    'active'
FROM generate_series(1, 20) AS i
JOIN sku ON sku.id = ('01930000-0000-7000-8000-' || lpad((720 + i)::text, 12, '0'))::uuid
        AND sku.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 9. 每个 SPU 一张主图
INSERT INTO product_media (id, spu_id, media_type, url, sort_weight, is_main)
SELECT
    ('01930000-0000-7000-8000-' || lpad((760 + i)::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid,
    'image',
    '/static/demo/spu/' || lpad(i::text, 4, '0') || '.jpg',
    0,
    true
FROM generate_series(1, 20) AS i
JOIN spu ON spu.id = ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid
        AND spu.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 10. 每个 SPU 一条详情
INSERT INTO product_detail (id, spu_id, content, content_html, version)
SELECT
    ('01930000-0000-7000-8000-' || lpad((780 + i)::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid,
    '{"blocks":[]}'::jsonb,
    '<p>演示商品详情</p>',
    1
FROM generate_series(1, 20) AS i
JOIN spu ON spu.id = ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid
        AND spu.deleted_at IS NULL
ON CONFLICT DO NOTHING;

-- 11. 每个 SPU 一个平台标签
INSERT INTO product_tag (id, spu_id, tag_code, tag_name, source, sort_weight)
SELECT
    ('01930000-0000-7000-8000-' || lpad((800 + i)::text, 12, '0'))::uuid,
    ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid,
    'new',
    '新品',
    'platform',
    0
FROM generate_series(1, 20) AS i
JOIN spu ON spu.id = ('01930000-0000-7000-8000-' || lpad((700 + i)::text, 12, '0'))::uuid
        AND spu.deleted_at IS NULL
ON CONFLICT DO NOTHING;

COMMIT;
