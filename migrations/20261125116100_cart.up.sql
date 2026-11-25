CREATE TABLE cart (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    item_count INTEGER NOT NULL DEFAULT 0,
    total_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    last_active_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_cart_item_count CHECK (item_count >= 0),
    CONSTRAINT ck_cart_total_amount CHECK (total_amount >= 0),
    CONSTRAINT ck_cart_status CHECK (status IN ('active', 'merged', 'abandoned'))
);

CREATE UNIQUE INDEX uq_cart_user_id ON cart (user_id) WHERE deleted_at IS NULL;
