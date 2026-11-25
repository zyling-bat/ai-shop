CREATE TABLE user_profile (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    gender VARCHAR(8) NOT NULL DEFAULT 'unknown',
    birthday DATE,
    real_name_enc TEXT,
    id_card_hash VARCHAR(64),
    id_card_enc TEXT,
    province VARCHAR(64),
    city VARCHAR(64),
    district VARCHAR(64),
    bio VARCHAR(255),
    extra JSONB NOT NULL DEFAULT '{}'::jsonb,
    realname_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_user_profile_gender CHECK (gender IN ('unknown', 'male', 'female'))
);

CREATE UNIQUE INDEX uq_user_profile_user_id ON user_profile (user_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_user_profile_id_card_hash ON user_profile (id_card_hash) WHERE id_card_hash IS NOT NULL AND deleted_at IS NULL;
