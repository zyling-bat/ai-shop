-- 登录日志：只增不改，deleted_at 仅为满足通用列约定。
CREATE TABLE login_log (
    id UUID PRIMARY KEY,
    user_id UUID,
    login_type VARCHAR(16) NOT NULL,
    channel VARCHAR(32) NOT NULL,
    success BOOLEAN NOT NULL,
    fail_reason VARCHAR(64),
    ip INET,
    user_agent TEXT,
    device_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_login_log_type CHECK (login_type IN ('password', 'sms', 'oauth', 'refresh'))
);

CREATE INDEX ix_login_log_user_id_created_at ON login_log (user_id, created_at DESC);
CREATE INDEX ix_login_log_ip_created_at ON login_log (ip, created_at DESC);
CREATE INDEX ix_login_log_created_at ON login_log (created_at DESC);
