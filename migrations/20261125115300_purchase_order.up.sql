CREATE TABLE purchase_order (
    id UUID PRIMARY KEY,
    po_no VARCHAR(32) NOT NULL,
    merchant_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    total_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    expected_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    remark VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_purchase_order_status CHECK (status IN ('draft', 'approving', 'approved', 'ordered', 'partially_received', 'received', 'settled', 'closed', 'cancelled')),
    CONSTRAINT ck_purchase_order_total_amount CHECK (total_amount >= 0)
);

CREATE UNIQUE INDEX uq_purchase_order_no ON purchase_order (po_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_purchase_order_supplier_id ON purchase_order (supplier_id, status);
CREATE INDEX ix_purchase_order_status ON purchase_order (status, created_at DESC);
