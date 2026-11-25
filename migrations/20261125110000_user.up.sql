-- 身份主表。user 是 PostgreSQL 保留字，迁移与查询必须写作 "user"。
CREATE TABLE "user" (
    id UUID PRIMARY KEY,
    phone_hash VARCHAR(64) NOT NULL,
    phone_enc TEXT NOT NULL,
    email_hash VARCHAR(64),
    email_enc TEXT,
    nickname VARCHAR(64) NOT NULL DEFAULT '',
    avatar TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    realname_status VARCHAR(32) NOT NULL DEFAULT 'unverified',
    level_id UUID,
    points_balance BIGINT NOT NULL DEFAULT 0,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_user_status CHECK (status IN ('active', 'frozen', 'cancelled')),
    CONSTRAINT ck_user_realname_status CHECK (realname_status IN ('unverified', 'pending', 'verified', 'rejected')),
    CONSTRAINT ck_user_points_balance CHECK (points_balance >= 0)
);

CREATE UNIQUE INDEX uq_user_phone_hash ON "user" (phone_hash) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_user_email_hash ON "user" (email_hash) WHERE deleted_at IS NULL;
CREATE INDEX ix_user_status_created_at ON "user" (status, created_at DESC);
CREATE INDEX ix_user_level_id ON "user" (level_id);
