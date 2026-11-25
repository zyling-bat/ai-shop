CREATE TABLE purchase_order_item (
    id UUID PRIMARY KEY,
    po_no VARCHAR(32) NOT NULL,
    sku_id UUID NOT NULL,
    qty INTEGER NOT NULL,
    received_qty INTEGER NOT NULL DEFAULT 0,
    price_amount NUMERIC(20,4) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_purchase_order_item_qty CHECK (qty > 0),
    CONSTRAINT ck_purchase_order_item_received_qty CHECK (received_qty >= 0 AND received_qty <= qty),
    CONSTRAINT ck_purchase_order_item_price_amount CHECK (price_amount >= 0)
);

CREATE UNIQUE INDEX uq_purchase_order_item_po_sku ON purchase_order_item (po_no, sku_id) WHERE deleted_at IS NULL;
