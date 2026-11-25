CREATE TABLE category (
    id UUID PRIMARY KEY,
    parent_id UUID,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(64) NOT NULL,
    level SMALLINT NOT NULL DEFAULT 1,
    path TEXT NOT NULL DEFAULT '/',
    icon TEXT,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    is_leaf BOOLEAN NOT NULL DEFAULT true,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_category_level CHECK (level >= 1),
    CONSTRAINT ck_category_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_category_code ON category (code) WHERE deleted_at IS NULL;
CREATE INDEX ix_category_parent_id ON category (parent_id, sort_weight);
CREATE INDEX ix_category_status_level ON category (status, level);
