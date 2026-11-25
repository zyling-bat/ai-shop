CREATE TABLE sku_spec (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    attr_id UUID NOT NULL,
    attr_value_id UUID,
    spec_value VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_sku_spec_sku_attr ON sku_spec (sku_id, attr_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_sku_spec_attr_value_id ON sku_spec (attr_id, attr_value_id);
