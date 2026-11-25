CREATE TABLE cart_item (
    id UUID PRIMARY KEY,
    cart_id UUID NOT NULL,
    user_id UUID NOT NULL,
    merchant_id UUID NOT NULL,
    shop_id UUID NOT NULL,
    spu_id UUID NOT NULL,
    sku_id UUID NOT NULL,
    qty INTEGER NOT NULL,
    price_amount NUMERIC(20,4) NOT NULL,
    selected BOOLEAN NOT NULL DEFAULT true,
    sku_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_cart_item_qty CHECK (qty > 0),
    CONSTRAINT ck_cart_item_price_amount CHECK (price_amount >= 0)
);

CREATE UNIQUE INDEX uq_cart_item_cart_sku ON cart_item (cart_id, sku_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_cart_item_user_id ON cart_item (user_id, updated_at DESC);
