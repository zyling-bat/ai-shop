CREATE TABLE stock_allocate_rule (
    id UUID PRIMARY KEY,
    merchant_id UUID,
    warehouse_id UUID NOT NULL,
    rule_type VARCHAR(16) NOT NULL DEFAULT 'priority',
    region_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    min_qty INTEGER NOT NULL DEFAULT 0,
    priority INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_stock_allocate_rule_type CHECK (rule_type IN ('priority', 'region', 'split')),
    CONSTRAINT ck_stock_allocate_rule_min_qty CHECK (min_qty >= 0),
    CONSTRAINT ck_stock_allocate_rule_status CHECK (status IN ('active', 'disabled'))
);

CREATE INDEX ix_stock_allocate_rule_warehouse_id ON stock_allocate_rule (warehouse_id, priority);
CREATE INDEX ix_stock_allocate_rule_merchant_id ON stock_allocate_rule (merchant_id) WHERE merchant_id IS NOT NULL AND deleted_at IS NULL;
