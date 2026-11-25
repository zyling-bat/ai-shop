CREATE TABLE user_identity (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    channel VARCHAR(32) NOT NULL,
    external_id VARCHAR(128) NOT NULL,
    union_id VARCHAR(128),
    bound_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_user_identity_channel CHECK (channel IN ('wechat', 'apple', 'phone', 'email'))
);

CREATE UNIQUE INDEX uq_user_identity_channel_external_id ON user_identity (channel, external_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_user_identity_user_id ON user_identity (user_id);
CREATE INDEX ix_user_identity_union_id ON user_identity (union_id) WHERE union_id IS NOT NULL AND deleted_at IS NULL;
