-- ST-1.1 / ST-1.2 约束断言：只读校验 + 事务内非法写入回滚，可重复执行。
-- 用法：psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/verify_p1_constraints.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
    ok boolean;
BEGIN
    -- 1. 表存在
    IF to_regclass('public.idempotency_record') IS NULL THEN
        RAISE EXCEPTION '断言失败：idempotency_record 不存在';
    END IF;
    IF to_regclass('public.outbox_event') IS NULL THEN
        RAISE EXCEPTION '断言失败：outbox_event 不存在';
    END IF;

    -- 2. 幂等表 (scope, key) 部分唯一索引
    SELECT i.indisunique
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_idempotency_record_scope_key';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_idempotency_record_scope_key 缺失、非唯一或缺少软删条件';
    END IF;

    -- 3. outbox event_id 部分唯一索引
    SELECT i.indisunique
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_outbox_event_event_id';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_outbox_event_event_id 缺失、非唯一或缺少软删条件';
    END IF;

    -- 4. 投递扫描索引 (status, next_retry_at)
    SELECT pg_get_indexdef(i.indexrelid) ILIKE '%(status, next_retry_at)%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'ix_outbox_event_status_next_retry_at';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：ix_outbox_event_status_next_retry_at 缺失或列顺序不符';
    END IF;

    -- 5. CHECK 约束存在
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_idempotency_record_status' AND contype = 'c'
    ) THEN
        RAISE EXCEPTION '断言失败：ck_idempotency_record_status 缺失';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_outbox_event_status' AND contype = 'c'
    ) THEN
        RAISE EXCEPTION '断言失败：ck_outbox_event_status 缺失';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_outbox_event_retry_count' AND contype = 'c'
    ) THEN
        RAISE EXCEPTION '断言失败：ck_outbox_event_retry_count 缺失';
    END IF;

    -- 6. 非法状态值必须被拒绝（子块回滚，不留数据）
    BEGIN
        INSERT INTO idempotency_record (id, scope, key, request_hash, status, expires_at)
        VALUES (gen_random_uuid(), 'verify', 'verify-status', repeat('a', 64), 'bogus', now());
        RAISE EXCEPTION '断言失败：idempotency_record.status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO outbox_event (id, event_id, aggregate_type, aggregate_id, event_type, payload, status)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'verify', 'verify', 'verify.created', '{}'::jsonb, 'bogus');
        RAISE EXCEPTION '断言失败：outbox_event.status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO outbox_event (id, event_id, aggregate_type, aggregate_id, event_type, payload, retry_count)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'verify', 'verify', 'verify.created', '{}'::jsonb, -1);
        RAISE EXCEPTION '断言失败：outbox_event.retry_count 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'P1 ST-1.1 约束断言全部通过';
END;
$$;

-- ST-1.2 身份与权限域断言：只读校验 + 事务内非法写入回滚，可重复执行。
DO $$
DECLARE
    ok boolean;
    tbl text;
    idx text;
BEGIN
    -- 1. 10 张表存在（user 是保留字，必须用 quote_ident 生成 "user"）
    FOREACH tbl IN ARRAY ARRAY[
        'user', 'user_identity', 'user_profile', 'user_device', 'login_log',
        'role', 'permission', 'role_permission', 'user_role', 'staff_account'
    ] LOOP
        IF to_regclass('public.' || quote_ident(tbl)) IS NULL THEN
            RAISE EXCEPTION '断言失败：% 不存在', tbl;
        END IF;
    END LOOP;

    -- 2. 部分唯一索引：唯一 + WHERE deleted_at IS NULL
    FOREACH idx IN ARRAY ARRAY[
        'uq_user_phone_hash', 'uq_user_email_hash',
        'uq_user_identity_channel_external_id', 'uq_user_profile_user_id',
        'uq_user_device_user_id_device_id', 'uq_role_code',
        'uq_permission_code', 'uq_role_permission_role_permission'
    ] LOOP
        SELECT i.indisunique
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
        INTO ok
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = idx;

        IF NOT COALESCE(ok, false) THEN
            RAISE EXCEPTION '断言失败：% 缺失、非唯一或缺少软删条件', idx;
        END IF;
    END LOOP;

    -- 3. NULLS NOT DISTINCT 唯一索引（平台级授权 scope_id 为空时防重复）
    FOREACH idx IN ARRAY ARRAY['uq_user_role_user_role_scope', 'uq_staff_account_user_merchant_shop'] LOOP
        SELECT i.indisunique
               AND i.indnullsnotdistinct
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
        INTO ok
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = idx;

        IF NOT COALESCE(ok, false) THEN
            RAISE EXCEPTION '断言失败：% 缺失、非唯一、未启用 NULLS NOT DISTINCT 或缺少软删条件', idx;
        END IF;
    END LOOP;

    -- 4. CHECK 约束存在
    FOREACH idx IN ARRAY ARRAY[
        'ck_user_status', 'ck_user_realname_status', 'ck_user_points_balance',
        'ck_user_identity_channel', 'ck_user_profile_gender', 'ck_user_device_type',
        'ck_login_log_type', 'ck_role_scope', 'ck_role_status',
        'ck_user_role_scope_type', 'ck_staff_account_scope', 'ck_staff_account_status'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = idx AND contype = 'c'
        ) THEN
            RAISE EXCEPTION '断言失败：CHECK 约束 % 缺失', idx;
        END IF;
    END LOOP;

    -- 5. 关键列与可空性
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user'
          AND column_name = 'phone_hash' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION '断言失败：user.phone_hash 缺失或允许为空';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user'
          AND column_name = 'phone_enc' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION '断言失败：user.phone_enc 缺失或允许为空';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user' AND column_name = 'points_balance'
    ) THEN
        RAISE EXCEPTION '断言失败：user.points_balance 缺失';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user_identity' AND column_name = 'channel'
    ) THEN
        RAISE EXCEPTION '断言失败：user_identity.channel 缺失';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'login_log' AND column_name = 'success'
    ) THEN
        RAISE EXCEPTION '断言失败：login_log.success 缺失';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'staff_account' AND column_name = 'is_primary'
    ) THEN
        RAISE EXCEPTION '断言失败：staff_account.is_primary 缺失';
    END IF;

    -- 6. 非法写入必须被拒绝（每个子块独立回滚，不留数据）
    BEGIN
        INSERT INTO "user" (id, phone_hash, phone_enc, status)
        VALUES (gen_random_uuid(), 'verify-phone-hash-status', 'verify-phone-enc', 'bogus');
        RAISE EXCEPTION '断言失败："user".status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO "user" (id, phone_hash, phone_enc, points_balance)
        VALUES (gen_random_uuid(), 'verify-phone-hash-points', 'verify-phone-enc', -1);
        RAISE EXCEPTION '断言失败："user".points_balance 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO role (id, code, name, scope)
        VALUES (gen_random_uuid(), 'verify_bad_scope_role', 'verify', 'bogus');
        RAISE EXCEPTION '断言失败：role.scope 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO user_role (id, user_id, role_id, scope_type)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'bogus');
        RAISE EXCEPTION '断言失败：user_role.scope_type 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO staff_account (id, user_id, shop_id)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());
        RAISE EXCEPTION '断言失败：staff_account 接受了“有店铺无商家”的组合';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'P1 ST-1.2 身份与权限域约束断言全部通过';
END;
$$;

-- ST-1.3 商家域断言：只读校验 + 事务内非法写入回滚，可重复执行。
DO $$
DECLARE
    ok boolean;
    tbl text;
    idx text;
BEGIN
    -- 1. 12 张表存在
    FOREACH tbl IN ARRAY ARRAY[
        'merchant', 'merchant_qualification', 'merchant_contract', 'shop',
        'shop_decoration', 'shop_score', 'shop_category_auth',
        'merchant_violation', 'merchant_appeal',
        'deposit_account', 'deposit_record', 'merchant_bank_account'
    ] LOOP
        IF to_regclass('public.' || quote_ident(tbl)) IS NULL THEN
            RAISE EXCEPTION '断言失败：% 不存在', tbl;
        END IF;
    END LOOP;

    -- 2. 部分唯一索引：唯一 + WHERE deleted_at IS NULL
    FOREACH idx IN ARRAY ARRAY[
        'uq_merchant_merchant_no', 'uq_merchant_contract_contract_no',
        'uq_shop_shop_no', 'uq_shop_decoration_shop_page_version',
        'uq_shop_score_shop_date', 'uq_shop_category_auth_shop_category',
        'uq_merchant_appeal_appeal_no', 'uq_deposit_account_merchant_id',
        'uq_deposit_record_record_no', 'uq_merchant_bank_account_no'
    ] LOOP
        SELECT i.indisunique
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
        INTO ok
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = idx;

        IF NOT COALESCE(ok, false) THEN
            RAISE EXCEPTION '断言失败：% 缺失、非唯一或缺少软删条件', idx;
        END IF;
    END LOOP;

    -- 3. 带业务过滤条件的唯一索引
    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%business_license%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_merchant_qualification_merchant_type';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_merchant_qualification_merchant_type 缺失或未限定执照/法人证件';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_published%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_shop_decoration_published';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_shop_decoration_published 缺失或未限定 is_published';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_default%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_merchant_bank_account_default';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_merchant_bank_account_default 缺失或未限定 is_default';
    END IF;

    -- 4. CHECK 约束存在
    FOREACH idx IN ARRAY ARRAY[
        'ck_merchant_type', 'ck_merchant_status', 'ck_merchant_settle_cycle', 'ck_merchant_commission_rate',
        'ck_merchant_qualification_type', 'ck_merchant_qualification_status', 'ck_merchant_qualification_period',
        'ck_merchant_contract_type', 'ck_merchant_contract_status', 'ck_merchant_contract_settle_cycle',
        'ck_merchant_contract_commission_rate', 'ck_merchant_contract_period',
        'ck_shop_status', 'ck_shop_dsr_desc', 'ck_shop_dsr_service', 'ck_shop_dsr_logistics',
        'ck_shop_decoration_page', 'ck_shop_decoration_version',
        'ck_shop_score_dsr_desc', 'ck_shop_score_dsr_service', 'ck_shop_score_dsr_logistics',
        'ck_shop_score_review_count', 'ck_shop_score_good_rate',
        'ck_shop_category_auth_status', 'ck_shop_category_auth_source',
        'ck_shop_category_auth_rate', 'ck_shop_category_auth_period',
        'ck_merchant_violation_type', 'ck_merchant_violation_level', 'ck_merchant_violation_penalty_type',
        'ck_merchant_violation_penalty_amount', 'ck_merchant_violation_points_deduct', 'ck_merchant_violation_status',
        'ck_merchant_appeal_type', 'ck_merchant_appeal_status', 'ck_merchant_appeal_violation',
        'ck_deposit_account_balance_amount', 'ck_deposit_account_frozen_amount', 'ck_deposit_account_frozen_le_balance',
        'ck_deposit_record_direction', 'ck_deposit_record_amount', 'ck_deposit_record_balance_after',
        'ck_deposit_record_biz_type', 'ck_deposit_record_status',
        'ck_merchant_bank_account_status'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = idx AND contype = 'c'
        ) THEN
            RAISE EXCEPTION '断言失败：CHECK 约束 % 缺失', idx;
        END IF;
    END LOOP;

    -- 5. 关键列与精度
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'shop'
          AND column_name = 'dsr_desc' AND numeric_precision = 3 AND numeric_scale = 2
    ) THEN
        RAISE EXCEPTION '断言失败：shop.dsr_desc 缺失或精度不是 NUMERIC(3,2)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'merchant'
          AND column_name = 'commission_rate' AND numeric_precision = 10 AND numeric_scale = 6
    ) THEN
        RAISE EXCEPTION '断言失败：merchant.commission_rate 缺失或精度不是 NUMERIC(10,6)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'deposit_account'
          AND column_name = 'balance_amount' AND numeric_precision = 20 AND numeric_scale = 4
    ) THEN
        RAISE EXCEPTION '断言失败：deposit_account.balance_amount 缺失或精度不是 NUMERIC(20,4)';
    END IF;

    -- 6. 非法写入必须被拒绝（每个子块独立回滚，不留数据）
    BEGIN
        INSERT INTO merchant (id, merchant_no, name, type, status)
        VALUES (gen_random_uuid(), 'VERIFY_BAD_STATUS', 'verify', 'company', 'bogus');
        RAISE EXCEPTION '断言失败：merchant.status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO merchant (id, merchant_no, name, type, commission_rate)
        VALUES (gen_random_uuid(), 'VERIFY_BAD_RATE', 'verify', 'company', 1.5);
        RAISE EXCEPTION '断言失败：merchant.commission_rate 接受了大于 1 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO shop (id, merchant_id, shop_no, name, dsr_desc)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'VERIFY_BAD_DSR', 'verify', 6);
        RAISE EXCEPTION '断言失败：shop.dsr_desc 接受了大于 5 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO deposit_account (id, merchant_id, balance_amount)
        VALUES (gen_random_uuid(), gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败：deposit_account.balance_amount 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO deposit_account (id, merchant_id, balance_amount, frozen_amount)
        VALUES (gen_random_uuid(), gen_random_uuid(), 10, 20);
        RAISE EXCEPTION '断言失败：deposit_account 接受了冻结金额大于余额的组合';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO deposit_record (id, account_id, merchant_id, record_no, direction, amount, balance_after, biz_type)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'VERIFY_BAD_AMOUNT', 'in', 0, 0, 'recharge');
        RAISE EXCEPTION '断言失败：deposit_record.amount 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- 同一页面只能有一个已发布版本
    BEGIN
        INSERT INTO shop_decoration (id, shop_id, page, version, is_published)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009901'::uuid, 'home', 1, true);

        BEGIN
            INSERT INTO shop_decoration (id, shop_id, page, version, is_published)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009901'::uuid, 'home', 2, true);
            RAISE EXCEPTION '断言失败：shop_decoration 接受了同页面两个已发布版本';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_decoration';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_decoration' THEN
                RAISE;
            END IF;
    END;

    -- 每个商家只能有一个默认银行卡
    BEGIN
        INSERT INTO merchant_bank_account (id, merchant_id, account_no_enc, account_no_hash, account_no_last4, bank_name, holder, is_default)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009902'::uuid, 'enc-1', 'verify-hash-1', '0001', 'verify', 'verify', true);

        BEGIN
            INSERT INTO merchant_bank_account (id, merchant_id, account_no_enc, account_no_hash, account_no_last4, bank_name, holder, is_default)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009902'::uuid, 'enc-2', 'verify-hash-2', '0002', 'verify', 'verify', true);
            RAISE EXCEPTION '断言失败：merchant_bank_account 接受了同商家两个默认账户';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_bank';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_bank' THEN
                RAISE;
            END IF;
    END;

    -- 营业执照每个商家只能一份
    BEGIN
        INSERT INTO merchant_qualification (id, merchant_id, qual_type, file_url)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009903'::uuid, 'business_license', 'https://verify/1.pdf');

        BEGIN
            INSERT INTO merchant_qualification (id, merchant_id, qual_type, file_url)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009903'::uuid, 'business_license', 'https://verify/2.pdf');
            RAISE EXCEPTION '断言失败：merchant_qualification 接受了同商家两份营业执照';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_qualification';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_qualification' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'P1 ST-1.3 商家域约束断言全部通过';
END;
$$;

-- ST-1.4 商品域断言：只读校验 + 事务内非法写入回滚，可重复执行。
DO $$
DECLARE
    ok boolean;
    tbl text;
    idx text;
BEGIN
    -- 1. 18 张表存在
    FOREACH tbl IN ARRAY ARRAY[
        'category', 'category_attr', 'category_attr_value', 'brand',
        'spu', 'spu_attr_value', 'sku', 'sku_spec', 'sku_media', 'sku_price',
        'product_media', 'product_detail', 'product_audit',
        'freight_template', 'freight_template_rule',
        'product_tag', 'product_limit', 'product_qa'
    ] LOOP
        IF to_regclass('public.' || quote_ident(tbl)) IS NULL THEN
            RAISE EXCEPTION '断言失败：% 不存在', tbl;
        END IF;
    END LOOP;

    -- 2. 部分唯一索引：唯一 + WHERE deleted_at IS NULL
    FOREACH idx IN ARRAY ARRAY[
        'uq_category_code', 'uq_category_attr_category_code',
        'uq_category_attr_value_attr_value', 'uq_brand_name', 'uq_spu_spu_no',
        'uq_spu_attr_value_spu_attr', 'uq_sku_sku_no', 'uq_sku_spu_barcode',
        'uq_sku_spec_sku_attr', 'uq_sku_media_main', 'uq_product_media_main',
        'uq_product_detail_spu_id', 'uq_product_audit_target_round',
        'uq_freight_template_merchant_name', 'uq_product_tag_spu_tag',
        'uq_product_limit_scope_target_type'
    ] LOOP
        SELECT i.indisunique
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
        INTO ok
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = idx;

        IF NOT COALESCE(ok, false) THEN
            RAISE EXCEPTION '断言失败：% 缺失、非唯一或缺少软删条件', idx;
        END IF;
    END LOOP;

    -- 3. 带业务过滤条件的唯一索引
    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_main%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_sku_media_main';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_sku_media_main 缺失或未限定 is_main';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_main%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_product_media_main';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_product_media_main 缺失或未限定 is_main';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_default%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_freight_template_default';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_freight_template_default 缺失或未限定 is_default';
    END IF;

    -- 4. sku_price 唯一索引：唯一 + 软删条件 + NULLS NOT DISTINCT
    SELECT i.indisunique
           AND i.indnullsnotdistinct
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_sku_price_sku_type_region_start';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_sku_price_sku_type_region_start 缺失、非唯一、无软删条件或未启用 NULLS NOT DISTINCT';
    END IF;

    -- 5. CHECK 约束存在
    FOREACH idx IN ARRAY ARRAY[
        'ck_category_level', 'ck_category_status',
        'ck_category_attr_type', 'ck_category_attr_input_type', 'ck_category_attr_status',
        'ck_category_attr_value_status', 'ck_brand_status',
        'ck_spu_status', 'ck_spu_audit_status',
        'ck_sku_status', 'ck_sku_weight_g', 'ck_sku_volume_cm3', 'ck_sku_version',
        'ck_sku_media_type',
        'ck_sku_price_type', 'ck_sku_price_amount', 'ck_sku_price_min_qty',
        'ck_sku_price_max_qty', 'ck_sku_price_period', 'ck_sku_price_status',
        'ck_product_media_type', 'ck_product_detail_version',
        'ck_product_audit_target_type', 'ck_product_audit_status', 'ck_product_audit_result',
        'ck_product_audit_round', 'ck_product_audit_machine_score',
        'ck_freight_template_charge_type', 'ck_freight_template_free_threshold', 'ck_freight_template_status',
        'ck_freight_template_rule_first_qty', 'ck_freight_template_rule_first_amount',
        'ck_freight_template_rule_extra_qty', 'ck_freight_template_rule_extra_amount',
        'ck_product_tag_source',
        'ck_product_limit_scope', 'ck_product_limit_type', 'ck_product_limit_qty',
        'ck_product_limit_period', 'ck_product_limit_status',
        'ck_product_qa_source', 'ck_product_qa_status'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = idx AND contype = 'c'
        ) THEN
            RAISE EXCEPTION '断言失败：CHECK 约束 % 缺失', idx;
        END IF;
    END LOOP;

    -- 6. 关键列类型与精度
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'sku_price'
          AND column_name = 'price_amount' AND numeric_precision = 20 AND numeric_scale = 4
    ) THEN
        RAISE EXCEPTION '断言失败：sku_price.price_amount 缺失或精度不是 NUMERIC(20,4)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'product_audit'
          AND column_name = 'machine_score' AND numeric_precision = 5 AND numeric_scale = 2
    ) THEN
        RAISE EXCEPTION '断言失败：product_audit.machine_score 缺失或精度不是 NUMERIC(5,2)';
    END IF;

    -- 7. 非法写入必须被拒绝（每个子块独立回滚，不留数据）
    BEGIN
        INSERT INTO spu (id, spu_no, merchant_id, shop_id, category_id, title, status)
        VALUES (gen_random_uuid(), 'VERIFY_BAD_SPU_STATUS', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'verify', 'bogus');
        RAISE EXCEPTION '断言失败：spu.status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO sku (id, sku_no, spu_id, version)
        VALUES (gen_random_uuid(), 'VERIFY_BAD_SKU_VERSION', gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败：sku.version 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO sku_price (id, sku_id, price_type, price_amount)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'sale', -1);
        RAISE EXCEPTION '断言失败：sku_price.price_amount 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO sku_price (id, sku_id, price_type, price_amount, min_qty, max_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'tier', 10, 5, 3);
        RAISE EXCEPTION '断言失败：sku_price.max_qty 接受了小于 min_qty 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO product_audit (id, target_type, target_id, machine_score)
        VALUES (gen_random_uuid(), 'spu', gen_random_uuid(), 101);
        RAISE EXCEPTION '断言失败：product_audit.machine_score 接受了大于 100 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO product_limit (id, scope, target_id, limit_type, limit_qty)
        VALUES (gen_random_uuid(), 'skuy', gen_random_uuid(), 'per_user', 1);
        RAISE EXCEPTION '断言失败：product_limit.scope 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO product_limit (id, scope, target_id, limit_type, limit_qty)
        VALUES (gen_random_uuid(), 'sku', gen_random_uuid(), 'per_user', 0);
        RAISE EXCEPTION '断言失败：product_limit.limit_qty 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO freight_template_rule (id, template_id, first_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), 0);
        RAISE EXCEPTION '断言失败：freight_template_rule.first_qty 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- 每个 SPU 只能有一张主图
    BEGIN
        INSERT INTO product_media (id, spu_id, media_type, url, is_main)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000008801'::uuid, 'image', 'https://verify/1.jpg', true);

        BEGIN
            INSERT INTO product_media (id, spu_id, media_type, url, is_main)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000008801'::uuid, 'image', 'https://verify/2.jpg', true);
            RAISE EXCEPTION '断言失败：product_media 接受了同一 SPU 两张主图';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_product_media';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_product_media' THEN
                RAISE;
            END IF;
    END;

    -- 每个商家只能有一个默认运费模板
    BEGIN
        INSERT INTO freight_template (id, merchant_id, name, is_default)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000008802'::uuid, 'verify-default-1', true);

        BEGIN
            INSERT INTO freight_template (id, merchant_id, name, is_default)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000008802'::uuid, 'verify-default-2', true);
            RAISE EXCEPTION '断言失败：freight_template 接受了同商家两个默认模板';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_freight';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_freight' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'P1 ST-1.4 商品域约束断言全部通过';
END;
$$;

