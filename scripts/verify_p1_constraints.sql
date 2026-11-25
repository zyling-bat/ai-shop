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

