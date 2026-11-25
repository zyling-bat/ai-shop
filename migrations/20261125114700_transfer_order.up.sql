CREATE TABLE transfer_order (
    id UUID PRIMARY KEY,
    transfer_no VARCHAR(32) NOT NULL,
    from_warehouse_id UUID NOT NULL,
    to_warehouse_id UUID NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'created',
    total_qty INTEGER NOT NULL DEFAULT 0,
    reason VARCHAR(255),
    expected_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_transfer_order_status CHECK (status IN ('created', 'approved', 'outbound', 'in_transit', 'inbound', 'completed', 'cancelled')),
    CONSTRAINT ck_transfer_order_total_qty CHECK (total_qty >= 0),
    CONSTRAINT ck_transfer_order_distinct_warehouse CHECK (from_warehouse_id <> to_warehouse_id)
);

CREATE UNIQUE INDEX uq_transfer_order_no ON transfer_order (transfer_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_transfer_order_status ON transfer_order (status, created_at DESC);
CREATE INDEX ix_transfer_order_from_warehouse_id ON transfer_order (from_warehouse_id, status);
CREATE INDEX ix_transfer_order_to_warehouse_id ON transfer_order (to_warehouse_id, status);
