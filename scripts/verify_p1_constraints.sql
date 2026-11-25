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

-- ST-1.5：库存与供应链域 21 张表
DO $$
DECLARE
    ok boolean;
    tbl text;
    idx text;
BEGIN
    -- 1. 21 张表存在
    FOREACH tbl IN ARRAY ARRAY[
        'warehouse', 'warehouse_zone',
        'sku_stock', 'sku_stock_batch', 'stock_log', 'stock_reserve', 'stock_allocate_rule',
        'transfer_order', 'transfer_order_item', 'stock_count', 'stock_count_item',
        'supplier', 'supplier_sku',
        'purchase_order', 'purchase_order_item',
        'inbound_order', 'inbound_order_item',
        'purchase_return', 'supplier_settlement', 'supplier_payment', 'production_order'
    ] LOOP
        IF to_regclass('public.' || quote_ident(tbl)) IS NULL THEN
            RAISE EXCEPTION '断言失败：% 不存在', tbl;
        END IF;
    END LOOP;

    -- 2. 部分唯一索引：唯一 + WHERE deleted_at IS NULL
    FOREACH idx IN ARRAY ARRAY[
        'uq_warehouse_no', 'uq_warehouse_zone_warehouse_zone_no',
        'uq_sku_stock_sku_warehouse', 'uq_sku_stock_batch_sku_warehouse_batch',
        'uq_stock_reserve_reserve_no', 'uq_stock_reserve_biz',
        'uq_transfer_order_no', 'uq_transfer_order_item_no_sku_batch',
        'uq_stock_count_no', 'uq_stock_count_item_no_sku_batch',
        'uq_supplier_no', 'uq_supplier_sku_supplier_sku',
        'uq_purchase_order_no', 'uq_purchase_order_item_po_sku',
        'uq_inbound_order_no', 'uq_inbound_order_item_no_sku_batch',
        'uq_purchase_return_no',
        'uq_supplier_settlement_no', 'uq_supplier_settlement_supplier_period',
        'uq_supplier_payment_no'
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
    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_default%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_warehouse_default';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_warehouse_default 缺失或未限定 is_default';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_primary%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_supplier_sku_primary';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_supplier_sku_primary 缺失或未限定 is_primary';
    END IF;

    SELECT i.indisunique AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%channel_txn_id IS NOT NULL%'
    INTO ok FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_supplier_payment_channel_txn';
    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：uq_supplier_payment_channel_txn 缺失或未限定 channel_txn_id';
    END IF;

    -- 4. NULLS NOT DISTINCT 尾批号唯一索引
    FOREACH idx IN ARRAY ARRAY[
        'uq_transfer_order_item_no_sku_batch',
        'uq_stock_count_item_no_sku_batch',
        'uq_inbound_order_item_no_sku_batch'
    ] LOOP
        SELECT i.indisunique
               AND i.indnullsnotdistinct
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%deleted_at IS NULL%'
        INTO ok
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = idx;

        IF NOT COALESCE(ok, false) THEN
            RAISE EXCEPTION '断言失败：% 缺失、非唯一、无软删条件或未启用 NULLS NOT DISTINCT', idx;
        END IF;
    END LOOP;

    -- 5. CHECK 约束存在（含 05 P1-2 点名的 sku_stock 三个 CHECK）
    FOREACH idx IN ARRAY ARRAY[
        'ck_warehouse_type', 'ck_warehouse_status',
        'ck_warehouse_zone_status',
        'ck_sku_stock_available_qty', 'ck_sku_stock_locked_qty', 'ck_sku_stock_occupied_qty',
        'ck_sku_stock_safety_qty', 'ck_sku_stock_version',
        'ck_sku_stock_batch_qty', 'ck_sku_stock_batch_period', 'ck_sku_stock_batch_status',
        'ck_stock_log_change_type',
        'ck_stock_reserve_biz_type', 'ck_stock_reserve_qty', 'ck_stock_reserve_status',
        'ck_stock_allocate_rule_type', 'ck_stock_allocate_rule_min_qty', 'ck_stock_allocate_rule_status',
        'ck_transfer_order_status', 'ck_transfer_order_total_qty', 'ck_transfer_order_distinct_warehouse',
        'ck_transfer_order_item_qty', 'ck_transfer_order_item_received_qty',
        'ck_stock_count_status', 'ck_stock_count_type',
        'ck_stock_count_item_book_qty', 'ck_stock_count_item_actual_qty', 'ck_stock_count_item_diff',
        'ck_supplier_type', 'ck_supplier_settle_cycle', 'ck_supplier_status',
        'ck_supplier_sku_supply_price', 'ck_supplier_sku_min_order_qty',
        'ck_supplier_sku_lead_time_days', 'ck_supplier_sku_status',
        'ck_purchase_order_status', 'ck_purchase_order_total_amount',
        'ck_purchase_order_item_qty', 'ck_purchase_order_item_received_qty',
        'ck_purchase_order_item_price_amount',
        'ck_inbound_order_status', 'ck_inbound_order_total_qty',
        'ck_inbound_order_item_qty', 'ck_inbound_order_item_received_qty',
        'ck_inbound_order_item_price_amount', 'ck_inbound_order_item_period',
        'ck_purchase_return_status', 'ck_purchase_return_total_qty', 'ck_purchase_return_total_amount',
        'ck_supplier_settlement_period', 'ck_supplier_settlement_gross_amount',
        'ck_supplier_settlement_return_amount', 'ck_supplier_settlement_net_amount',
        'ck_supplier_settlement_status',
        'ck_supplier_payment_amount', 'ck_supplier_payment_method', 'ck_supplier_payment_status',
        'ck_production_order_qty', 'ck_production_order_completed_qty', 'ck_production_order_status'
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
        WHERE table_schema = 'public' AND table_name = 'supplier_sku'
          AND column_name = 'supply_price' AND numeric_precision = 20 AND numeric_scale = 4
    ) THEN
        RAISE EXCEPTION '断言失败：supplier_sku.supply_price 缺失或精度不是 NUMERIC(20,4)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'purchase_order'
          AND column_name = 'total_amount' AND numeric_precision = 20 AND numeric_scale = 4
    ) THEN
        RAISE EXCEPTION '断言失败：purchase_order.total_amount 缺失或精度不是 NUMERIC(20,4)';
    END IF;

    -- 7. 非法写入必须被拒绝（每个子块独立回滚，不留数据）
    BEGIN
        INSERT INTO sku_stock (id, sku_id, warehouse_id, available_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败：sku_stock.available_qty 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO sku_stock (id, sku_id, warehouse_id, locked_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败：sku_stock.locked_qty 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO sku_stock (id, sku_id, warehouse_id, occupied_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败：sku_stock.occupied_qty 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO stock_reserve (id, reserve_no, biz_type, biz_no, sku_id, warehouse_id, qty)
        VALUES (gen_random_uuid(), 'VERIFY_RESERVE_ZERO', 'order', 'VERIFY_BIZ', gen_random_uuid(), gen_random_uuid(), 0);
        RAISE EXCEPTION '断言失败：stock_reserve.qty 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO transfer_order (id, transfer_no, from_warehouse_id, to_warehouse_id)
        VALUES (gen_random_uuid(), 'VERIFY_TRANSFER_SAME',
                '01930000-0000-7000-8000-000000009906'::uuid,
                '01930000-0000-7000-8000-000000009906'::uuid);
        RAISE EXCEPTION '断言失败：transfer_order 接受了同一出入库仓';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO stock_count_item (id, count_no, sku_id, book_qty, actual_qty, diff_qty)
        VALUES (gen_random_uuid(), 'VERIFY_COUNT_DIFF', gen_random_uuid(), 5, 3, 0);
        RAISE EXCEPTION '断言失败：stock_count_item.diff_qty 与 actual_qty - book_qty 不一致仍被接受';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO purchase_order_item (id, po_no, sku_id, qty, received_qty, price_amount)
        VALUES (gen_random_uuid(), 'VERIFY_PO_OVER', gen_random_uuid(), 3, 4, 10);
        RAISE EXCEPTION '断言失败：purchase_order_item.received_qty 接受了大于 qty 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO inbound_order_item (id, inbound_no, sku_id, qty, production_at, expire_at)
        VALUES (gen_random_uuid(), 'VERIFY_INBOUND_PERIOD', gen_random_uuid(), 1, DATE '2026-02-01', DATE '2026-01-01');
        RAISE EXCEPTION '断言失败：inbound_order_item.expire_at 早于 production_at 仍被接受';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO supplier_payment (id, payment_no, supplier_id, amount)
        VALUES (gen_random_uuid(), 'VERIFY_PAY_ZERO', gen_random_uuid(), 0);
        RAISE EXCEPTION '断言失败：supplier_payment.amount 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO supplier_settlement (id, settlement_no, supplier_id, period_start, period_end, gross_amount, return_amount, net_amount)
        VALUES (gen_random_uuid(), 'VERIFY_SETTLE_NET', gen_random_uuid(), DATE '2026-01-01', DATE '2026-01-31', 100, 10, 0);
        RAISE EXCEPTION '断言失败：supplier_settlement.net_amount 与 gross - return 不一致仍被接受';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO production_order (id, production_no, supplier_id, sku_id, qty, completed_qty)
        VALUES (gen_random_uuid(), 'VERIFY_PROD_OVER', gen_random_uuid(), gen_random_uuid(), 2, 3);
        RAISE EXCEPTION '断言失败：production_order.completed_qty 接受了大于 qty 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- 同一 SKU 同一仓库只能有一条库存
    BEGIN
        INSERT INTO sku_stock (id, sku_id, warehouse_id, available_qty)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009901'::uuid, '01930000-0000-7000-8000-000000009902'::uuid, 10);

        BEGIN
            INSERT INTO sku_stock (id, sku_id, warehouse_id, available_qty)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000009901'::uuid, '01930000-0000-7000-8000-000000009902'::uuid, 20);
            RAISE EXCEPTION '断言失败：sku_stock 接受了同一 SKU 同一仓库两条库存';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_sku_stock';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_sku_stock' THEN
                RAISE;
            END IF;
    END;

    -- 同一单据同一 SKU 同一仓库同一状态只能有一条预占
    BEGIN
        INSERT INTO stock_reserve (id, reserve_no, biz_type, biz_no, sku_id, warehouse_id, qty, status)
        VALUES (gen_random_uuid(), 'VERIFY_RESERVE_1', 'order', 'VERIFY_BIZ_DUP', '01930000-0000-7000-8000-000000009903'::uuid, '01930000-0000-7000-8000-000000009904'::uuid, 2, 'reserved');

        BEGIN
            INSERT INTO stock_reserve (id, reserve_no, biz_type, biz_no, sku_id, warehouse_id, qty, status)
            VALUES (gen_random_uuid(), 'VERIFY_RESERVE_2', 'order', 'VERIFY_BIZ_DUP', '01930000-0000-7000-8000-000000009903'::uuid, '01930000-0000-7000-8000-000000009904'::uuid, 3, 'reserved');
            RAISE EXCEPTION '断言失败：stock_reserve 接受了重复预占';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_stock_reserve';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_stock_reserve' THEN
                RAISE;
            END IF;
    END;

    -- 同一渠道流水号只能出账一次
    BEGIN
        INSERT INTO supplier_payment (id, payment_no, supplier_id, amount, pay_method, channel_txn_id)
        VALUES (gen_random_uuid(), 'VERIFY_PAY_1', '01930000-0000-7000-8000-000000009905'::uuid, 10, 'bank', 'VERIFY_TXN_DUP');

        BEGIN
            INSERT INTO supplier_payment (id, payment_no, supplier_id, amount, pay_method, channel_txn_id)
            VALUES (gen_random_uuid(), 'VERIFY_PAY_2', '01930000-0000-7000-8000-000000009905'::uuid, 20, 'bank', 'VERIFY_TXN_DUP');
            RAISE EXCEPTION '断言失败：supplier_payment 接受了重复渠道流水号';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_supplier_payment';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_supplier_payment' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'P1 ST-1.5 库存与供应链域约束断言全部通过';
END;
$$;

-- ST-1.6 交易域断言：只读校验 + 事务内非法写入回滚，可重复执行。
DO $$
DECLARE
    ok boolean;
    tbl text;
    idx text;
BEGIN
    -- 1. 12 张表存在（order 是保留字，quote_ident 会生成 "order"）
    FOREACH tbl IN ARRAY ARRAY[
        'cart', 'cart_item', 'order', 'order_item', 'order_amount_snapshot',
        'order_address', 'order_status_log', 'order_remark', 'order_tag',
        'invoice', 'invoice_item', 'price_calc_log'
    ] LOOP
        IF to_regclass('public.' || quote_ident(tbl)) IS NULL THEN
            RAISE EXCEPTION '断言失败：% 不存在', tbl;
        END IF;
    END LOOP;

    -- 2. 部分唯一索引：唯一 + WHERE deleted_at IS NULL（含 05 P1-2 点名的 uq_order_order_no）
    FOREACH idx IN ARRAY ARRAY[
        'uq_cart_user_id', 'uq_cart_item_cart_sku', 'uq_order_order_no',
        'uq_order_amount_snapshot_order_no', 'uq_order_address_order_type',
        'uq_order_tag_order_tag', 'uq_invoice_invoice_no',
        'uq_invoice_item_invoice_order_item'
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

    -- 3. 订单查询索引列序与部分条件
    SELECT pg_get_indexdef(i.indexrelid) ILIKE '%(user_id, status, created_at DESC)%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'ix_order_user_status_created';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：ix_order_user_status_created 缺失或列序不符';
    END IF;

    SELECT pg_get_indexdef(i.indexrelid) ILIKE '%(merchant_id, status, created_at DESC)%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'ix_order_merchant_status_created';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：ix_order_merchant_status_created 缺失或列序不符';
    END IF;

    SELECT pg_get_expr(i.indpred, i.indrelid) ILIKE '%pending_pay%'
    INTO ok
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'ix_order_pay_expire';

    IF NOT COALESCE(ok, false) THEN
        RAISE EXCEPTION '断言失败：ix_order_pay_expire 缺失或未限定 pending_pay';
    END IF;

    -- 4. CHECK 约束存在
    FOREACH idx IN ARRAY ARRAY[
        'ck_order_status', 'ck_order_order_type', 'ck_order_pay_status',
        'ck_order_ship_status', 'ck_order_after_sale_status', 'ck_order_channel',
        'ck_order_amounts_non_negative', 'ck_order_item_qty', 'ck_order_item_refund_qty',
        'ck_cart_item_qty', 'ck_invoice_amount', 'ck_invoice_item_tax_rate'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = idx AND contype = 'c'
        ) THEN
            RAISE EXCEPTION '断言失败：CHECK 约束 % 缺失', idx;
        END IF;
    END LOOP;

    -- 5. 精度
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'order'
          AND column_name = 'goods_amount'
          AND data_type = 'numeric' AND numeric_precision = 20 AND numeric_scale = 4
    ) THEN
        RAISE EXCEPTION '断言失败："order".goods_amount 不是 NUMERIC(20,4)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invoice_item'
          AND column_name = 'tax_rate'
          AND data_type = 'numeric' AND numeric_precision = 10 AND numeric_scale = 6
    ) THEN
        RAISE EXCEPTION '断言失败：invoice_item.tax_rate 不是 NUMERIC(10,6)';
    END IF;

    -- 6. 非法写入必须被拒绝（每个子块独立回滚，不留数据）
    BEGIN
        INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id, status)
        VALUES (gen_random_uuid(), 'VERIFY_SO_STATUS', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'bogus');
        RAISE EXCEPTION '断言失败："order".status 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id, order_type)
        VALUES (gen_random_uuid(), 'VERIFY_SO_TYPE', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'bogus');
        RAISE EXCEPTION '断言失败："order".order_type 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id, channel)
        VALUES (gen_random_uuid(), 'VERIFY_SO_CHANNEL', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'bogus');
        RAISE EXCEPTION '断言失败："order".channel 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id, goods_amount)
        VALUES (gen_random_uuid(), 'VERIFY_SO_AMOUNT', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), -1);
        RAISE EXCEPTION '断言失败："order".goods_amount 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO order_item (id, order_id, order_no, spu_id, sku_id, qty, unit_price, item_amount)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'VERIFY_SO_ITEM_QTY', gen_random_uuid(), gen_random_uuid(), 0, 1, 1);
        RAISE EXCEPTION '断言失败：order_item.qty 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO order_item (id, order_id, order_no, spu_id, sku_id, qty, unit_price, item_amount, refund_qty)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'VERIFY_SO_ITEM_REFUND', gen_random_uuid(), gen_random_uuid(), 2, 1, 2, 3);
        RAISE EXCEPTION '断言失败：order_item.refund_qty 接受了大于 qty 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO cart_item (id, cart_id, user_id, merchant_id, shop_id, spu_id, sku_id, qty, price_amount)
        VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 0, 1);
        RAISE EXCEPTION '断言失败：cart_item.qty 接受了 0';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO invoice (id, invoice_no, order_no, user_id, title, amount)
        VALUES (gen_random_uuid(), 'VERIFY_INV_AMOUNT', 'VERIFY_SO_INV', gen_random_uuid(), 'verify', -1);
        RAISE EXCEPTION '断言失败：invoice.amount 接受了负数';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO invoice_item (id, invoice_id, order_no, order_item_id, name, amount, tax_rate)
        VALUES (gen_random_uuid(), gen_random_uuid(), 'VERIFY_SO_INV_ITEM', gen_random_uuid(), 'verify', 1, 1.5);
        RAISE EXCEPTION '断言失败：invoice_item.tax_rate 接受了大于 1 的值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO order_address (id, order_no, address_type, receiver_name, receiver_phone_enc, province, city, district, detail_address)
        VALUES (gen_random_uuid(), 'VERIFY_SO_ADDR_TYPE', 'bogus', 'verify', 'verify-enc', '省', '市', '区', '地址');
        RAISE EXCEPTION '断言失败：order_address.address_type 接受了非法值';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- 7. 重复写入必须被唯一索引拒绝（子事务回滚）
    BEGIN
        INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id)
        VALUES (gen_random_uuid(), 'VERIFY_SO_DUP', gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

        BEGIN
            INSERT INTO "order" (id, order_no, user_id, merchant_id, shop_id)
            VALUES (gen_random_uuid(), 'VERIFY_SO_DUP', gen_random_uuid(), gen_random_uuid(), gen_random_uuid());
            RAISE EXCEPTION '断言失败："order" 接受了重复订单号';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_order_no';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_order_no' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        INSERT INTO cart_item (id, cart_id, user_id, merchant_id, shop_id, spu_id, sku_id, qty, price_amount)
        VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000001301'::uuid, gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), '01930000-0000-7000-8000-000000001302'::uuid, 1, 1);

        BEGIN
            INSERT INTO cart_item (id, cart_id, user_id, merchant_id, shop_id, spu_id, sku_id, qty, price_amount)
            VALUES (gen_random_uuid(), '01930000-0000-7000-8000-000000001301'::uuid, gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), '01930000-0000-7000-8000-000000001302'::uuid, 2, 1);
            RAISE EXCEPTION '断言失败：cart_item 接受了同车同 SKU 两条明细';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_cart_item';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_cart_item' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        INSERT INTO order_amount_snapshot (id, order_no, calc_version, input, output)
        VALUES (gen_random_uuid(), 'VERIFY_SO_SNAP', 'v1', '{}'::jsonb, '{}'::jsonb);

        BEGIN
            INSERT INTO order_amount_snapshot (id, order_no, calc_version, input, output)
            VALUES (gen_random_uuid(), 'VERIFY_SO_SNAP', 'v1', '{}'::jsonb, '{}'::jsonb);
            RAISE EXCEPTION '断言失败：order_amount_snapshot 接受了同一订单两份快照';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_order_snapshot';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_order_snapshot' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        INSERT INTO order_address (id, order_no, address_type, receiver_name, receiver_phone_enc, province, city, district, detail_address)
        VALUES (gen_random_uuid(), 'VERIFY_SO_ADDR_DUP', 'shipping', 'verify', 'verify-enc', '省', '市', '区', '地址');

        BEGIN
            INSERT INTO order_address (id, order_no, address_type, receiver_name, receiver_phone_enc, province, city, district, detail_address)
            VALUES (gen_random_uuid(), 'VERIFY_SO_ADDR_DUP', 'shipping', 'verify2', 'verify-enc2', '省', '市', '区', '地址2');
            RAISE EXCEPTION '断言失败：order_address 接受了同一订单两份收货地址';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        RAISE EXCEPTION 'rollback_verify_order_address';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> 'rollback_verify_order_address' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'P1 ST-1.6 交易域约束断言全部通过';
END;
$$;

