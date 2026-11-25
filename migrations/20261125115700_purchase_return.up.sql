CREATE TABLE purchase_return (
    id UUID PRIMARY KEY,
    return_no VARCHAR(32) NOT NULL,
    po_no VARCHAR(32),
    inbound_no VARCHAR(32),
    supplier_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    total_qty INTEGER NOT NULL DEFAULT 0,
    total_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_purchase_return_status CHECK (status IN ('draft', 'submitted', 'approved', 'shipped', 'completed', 'cancelled')),
    CONSTRAINT ck_purchase_return_total_qty CHECK (total_qty >= 0),
    CONSTRAINT ck_purchase_return_total_amount CHECK (total_amount >= 0)
);

CREATE UNIQUE INDEX uq_purchase_return_no ON purchase_return (return_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_purchase_return_supplier_id ON purchase_return (supplier_id, status);
