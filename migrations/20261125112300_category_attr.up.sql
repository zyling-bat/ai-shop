CREATE TABLE category_attr (
    id UUID PRIMARY KEY,
    category_id UUID NOT NULL,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(64) NOT NULL,
    attr_type VARCHAR(16) NOT NULL DEFAULT 'sale',
    input_type VARCHAR(16) NOT NULL DEFAULT 'text',
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_sku_attr BOOLEAN NOT NULL DEFAULT false,
    is_searchable BOOLEAN NOT NULL DEFAULT false,
    is_filterable BOOLEAN NOT NULL DEFAULT false,
    unit VARCHAR(16),
    sort_weight INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_category_attr_type CHECK (attr_type IN ('sale', 'key', 'prop')),
    CONSTRAINT ck_category_attr_input_type CHECK (input_type IN ('text', 'number', 'select', 'multi_select', 'bool')),
    CONSTRAINT ck_category_attr_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_category_attr_category_code ON category_attr (category_id, code) WHERE deleted_at IS NULL;
CREATE INDEX ix_category_attr_category_id ON category_attr (category_id, sort_weight);
