CREATE TABLE user_role (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    role_id UUID NOT NULL,
    scope_type VARCHAR(16) NOT NULL,
    scope_id UUID,
    granted_by UUID,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_user_role_scope_type CHECK (scope_type IN ('platform', 'merchant', 'shop'))
);

-- 平台级授权 scope_id 为空，必须用 NULLS NOT DISTINCT 才能防止重复插入（PG15+）。
CREATE UNIQUE INDEX uq_user_role_user_role_scope ON user_role (user_id, role_id, scope_type, scope_id) NULLS NOT DISTINCT WHERE deleted_at IS NULL;
CREATE INDEX ix_user_role_role_id ON user_role (role_id);
CREATE INDEX ix_user_role_scope ON user_role (scope_type, scope_id);
