CREATE TABLE inbound_order (
    id UUID PRIMARY KEY,
    inbound_no VARCHAR(32) NOT NULL,
    warehouse_id UUID NOT NULL,
    supplier_id UUID,
    po_no VARCHAR(32),
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    total_qty INTEGER NOT NULL DEFAULT 0,
    received_at TIMESTAMPTZ,
    operator_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_inbound_order_status CHECK (status IN ('draft', 'pending', 'receiving', 'completed', 'cancelled')),
    CONSTRAINT ck_inbound_order_total_qty CHECK (total_qty >= 0)
);

CREATE UNIQUE INDEX uq_inbound_order_no ON inbound_order (inbound_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_inbound_order_po_no ON inbound_order (po_no) WHERE po_no IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_inbound_order_warehouse_id ON inbound_order (warehouse_id, status);
