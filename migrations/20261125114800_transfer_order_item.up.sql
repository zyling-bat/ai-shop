CREATE TABLE transfer_order_item (
    id UUID PRIMARY KEY,
    transfer_no VARCHAR(32) NOT NULL,
    sku_id UUID NOT NULL,
    batch_no VARCHAR(64),
    qty INTEGER NOT NULL,
    received_qty INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_transfer_order_item_qty CHECK (qty > 0),
    CONSTRAINT ck_transfer_order_item_received_qty CHECK (received_qty >= 0 AND received_qty <= qty)
);

CREATE UNIQUE INDEX uq_transfer_order_item_no_sku_batch ON transfer_order_item (transfer_no, sku_id, batch_no)
    NULLS NOT DISTINCT WHERE deleted_at IS NULL;
