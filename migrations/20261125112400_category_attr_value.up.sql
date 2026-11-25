CREATE TABLE category_attr_value (
    id UUID PRIMARY KEY,
    attr_id UUID NOT NULL,
    value VARCHAR(128) NOT NULL,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_category_attr_value_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_category_attr_value_attr_value ON category_attr_value (attr_id, value) WHERE deleted_at IS NULL;
CREATE INDEX ix_category_attr_value_attr_id ON category_attr_value (attr_id, sort_weight);
