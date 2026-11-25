CREATE TABLE spu_attr_value (
    id UUID PRIMARY KEY,
    spu_id UUID NOT NULL,
    attr_id UUID NOT NULL,
    value_id UUID,
    attr_value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_spu_attr_value_spu_attr ON spu_attr_value (spu_id, attr_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_spu_attr_value_attr_id ON spu_attr_value (attr_id, value_id);
