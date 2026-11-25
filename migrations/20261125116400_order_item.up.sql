CREATE TABLE order_item (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL,
    order_no VARCHAR(32) NOT NULL,
    spu_id UUID NOT NULL,
    sku_id UUID NOT NULL,
    sku_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    qty INTEGER NOT NULL,
    unit_price NUMERIC(20,4) NOT NULL,
    item_amount NUMERIC(20,4) NOT NULL,
    discount_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    refund_qty INTEGER NOT NULL DEFAULT 0,
    refund_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    after_sale_status VARCHAR(16) NOT NULL DEFAULT 'none',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_item_qty CHECK (qty > 0),
    CONSTRAINT ck_order_item_amounts CHECK (
        unit_price >= 0
        AND item_amount >= 0
        AND discount_amount >= 0
        AND tax_amount >= 0
        AND refund_amount >= 0
    ),
    CONSTRAINT ck_order_item_refund_qty CHECK (refund_qty >= 0 AND refund_qty <= qty),
    CONSTRAINT ck_order_item_after_sale_status CHECK (
        after_sale_status IN ('none', 'applying', 'processing', 'finished')
    )
);

CREATE INDEX ix_order_item_order_id ON order_item (order_id);
CREATE INDEX ix_order_item_order_no ON order_item (order_no);
CREATE INDEX ix_order_item_sku_id ON order_item (sku_id, created_at DESC);
