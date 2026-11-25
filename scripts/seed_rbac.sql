-- ST-1.2 RBAC 基础种子：6 角色 / 15 权限 / 41 映射。
-- 可重复执行：所有写入 ON CONFLICT DO NOTHING，主键为确定性 UUIDv7 形态。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/seed_rbac.sql
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO role (id, code, name, scope, description, is_system)
SELECT ('01930000-0000-7000-8000-' || lpad(to_hex(v.seq), 12, '0'))::uuid,
       v.code, v.name, v.scope, v.description, true
FROM (VALUES
    (1, 'platform_admin',    '平台超级管理员', 'platform', '平台全量权限'),
    (2, 'platform_operator', '平台运营',       'platform', '平台日常运营，无系统配置与写操作权限'),
    (3, 'merchant_admin',    '商家管理员',     'merchant', '商家侧全量业务权限'),
    (4, 'merchant_operator', '商家运营',       'merchant', '商家侧日常运营权限'),
    (5, 'shop_admin',        '店铺管理员',     'shop',     '单店铺只读与订单查看'),
    (6, 'customer_service',  '客服',           'merchant', '订单查询与售后处理')
) AS v(seq, code, name, scope, description)
ON CONFLICT DO NOTHING;

INSERT INTO permission (id, code, name, resource, action, description)
SELECT ('01930000-0000-7000-8000-' || lpad(to_hex(100 + v.seq), 12, '0'))::uuid,
       v.code, v.name, v.resource, v.action, v.description
FROM (VALUES
    (1,  'user:read',          '用户查看', 'user',       'read',    '查看用户基础信息'),
    (2,  'user:manage',        '用户管理', 'user',       'manage',  '冻结、解冻、注销用户'),
    (3,  'merchant:read',      '商家查看', 'merchant',   'read',    '查看商家与资质'),
    (4,  'merchant:manage',    '商家管理', 'merchant',   'manage',  '审核、冻结、关闭商家'),
    (5,  'shop:read',          '店铺查看', 'shop',       'read',    '查看店铺信息'),
    (6,  'shop:manage',        '店铺管理', 'shop',       'manage',  '店铺状态与类目授权'),
    (7,  'product:read',       '商品查看', 'product',    'read',    '查看商品与审核记录'),
    (8,  'product:manage',     '商品管理', 'product',    'manage',  '商品审核与上下架'),
    (9,  'order:read',         '订单查看', 'order',      'read',    '查看订单与状态日志'),
    (10, 'order:manage',       '订单管理', 'order',      'manage',  '改价、关单、发货'),
    (11, 'after_sale:read',    '售后查看', 'after_sale', 'read',    '查看售后单'),
    (12, 'after_sale:manage',  '售后管理', 'after_sale', 'manage',  '审核、仲裁售后'),
    (13, 'settlement:read',    '结算查看', 'settlement', 'read',    '查看结算单与账单'),
    (14, 'settlement:manage',  '结算管理', 'settlement', 'manage',  '生成、调整结算单'),
    (15, 'system:config',      '系统配置', 'system',     'config',  '平台参数与功能开关')
) AS v(seq, code, name, resource, action, description)
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (id, role_id, permission_id)
SELECT ('01930000-0000-7000-8000-'
        || lpad(to_hex(200 + row_number() OVER (ORDER BY m.role_code, m.permission_code)), 12, '0'))::uuid,
       r.id, p.id
FROM (VALUES
    ('platform_admin',    'user:read'),
    ('platform_admin',    'user:manage'),
    ('platform_admin',    'merchant:read'),
    ('platform_admin',    'merchant:manage'),
    ('platform_admin',    'shop:read'),
    ('platform_admin',    'shop:manage'),
    ('platform_admin',    'product:read'),
    ('platform_admin',    'product:manage'),
    ('platform_admin',    'order:read'),
    ('platform_admin',    'order:manage'),
    ('platform_admin',    'after_sale:read'),
    ('platform_admin',    'after_sale:manage'),
    ('platform_admin',    'settlement:read'),
    ('platform_admin',    'settlement:manage'),
    ('platform_admin',    'system:config'),

    ('platform_operator', 'user:read'),
    ('platform_operator', 'merchant:read'),
    ('platform_operator', 'merchant:manage'),
    ('platform_operator', 'shop:read'),
    ('platform_operator', 'shop:manage'),
    ('platform_operator', 'product:read'),
    ('platform_operator', 'order:read'),
    ('platform_operator', 'after_sale:read'),
    ('platform_operator', 'settlement:read'),

    ('merchant_admin',    'product:read'),
    ('merchant_admin',    'product:manage'),
    ('merchant_admin',    'order:read'),
    ('merchant_admin',    'order:manage'),
    ('merchant_admin',    'after_sale:read'),
    ('merchant_admin',    'after_sale:manage'),
    ('merchant_admin',    'settlement:read'),

    ('merchant_operator', 'product:read'),
    ('merchant_operator', 'product:manage'),
    ('merchant_operator', 'order:read'),
    ('merchant_operator', 'after_sale:read'),

    ('shop_admin',        'product:read'),
    ('shop_admin',        'order:read'),
    ('shop_admin',        'after_sale:read'),

    ('customer_service',  'order:read'),
    ('customer_service',  'after_sale:read'),
    ('customer_service',  'after_sale:manage')
) AS m(role_code, permission_code)
JOIN role r ON r.code = m.role_code AND r.deleted_at IS NULL
JOIN permission p ON p.code = m.permission_code AND p.deleted_at IS NULL
ON CONFLICT DO NOTHING;

COMMIT;
