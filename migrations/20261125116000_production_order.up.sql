CREATE TABLE production_order (
    id UUID PRIMARY KEY,
    production_no VARCHAR(32) NOT NULL,
    supplier_id UUID NOT NULL,
    sku_id UUID NOT NULL,
    qty INTEGER NOT NULL,
    completed_qty INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    expected_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_production_order_qty CHECK (qty > 0),
    CONSTRAINT ck_production_order_completed_qty CHECK (completed_qty >= 0 AND completed_qty <= qty),
    CONSTRAINT ck_production_order_status CHECK (status IN ('draft', 'in_production', 'completed', 'cancelled'))
);

CREATE UNIQUE INDEX uq_production_order_no ON production_order (production_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_production_order_supplier_id ON production_order (supplier_id, status);
CREATE INDEX ix_production_order_sku_id ON production_order (sku_id, status);
