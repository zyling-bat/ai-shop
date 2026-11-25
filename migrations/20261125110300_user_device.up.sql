CREATE TABLE user_device (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    device_type VARCHAR(16) NOT NULL DEFAULT 'web',
    os VARCHAR(32),
    os_version VARCHAR(32),
    app_version VARCHAR(32),
    push_token VARCHAR(255),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_user_device_type CHECK (device_type IN ('web', 'h5', 'miniapp', 'app'))
);

CREATE UNIQUE INDEX uq_user_device_user_id_device_id ON user_device (user_id, device_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_user_device_device_id ON user_device (device_id);
