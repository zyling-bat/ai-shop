CREATE TABLE inbound_order_item (
    id UUID PRIMARY KEY,
    inbound_no VARCHAR(32) NOT NULL,
    sku_id UUID NOT NULL,
    batch_no VARCHAR(64),
    qty INTEGER NOT NULL,
    received_qty INTEGER NOT NULL DEFAULT 0,
    price_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    production_at DATE,
    expire_at DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_inbound_order_item_qty CHECK (qty > 0),
    CONSTRAINT ck_inbound_order_item_received_qty CHECK (received_qty >= 0 AND received_qty <= qty),
    CONSTRAINT ck_inbound_order_item_price_amount CHECK (price_amount >= 0),
    CONSTRAINT ck_inbound_order_item_period CHECK (production_at IS NULL OR expire_at IS NULL OR expire_at >= production_at)
);

CREATE UNIQUE INDEX uq_inbound_order_item_no_sku_batch ON inbound_order_item (inbound_no, sku_id, batch_no)
    NULLS NOT DISTINCT WHERE deleted_at IS NULL;
