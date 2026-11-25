CREATE TABLE order_address (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL,
    address_type VARCHAR(16) NOT NULL DEFAULT 'shipping',
    receiver_name VARCHAR(64) NOT NULL,
    receiver_phone_enc TEXT NOT NULL,
    province VARCHAR(64) NOT NULL,
    city VARCHAR(64) NOT NULL,
    district VARCHAR(64) NOT NULL,
    detail_address VARCHAR(255) NOT NULL,
    postal_code VARCHAR(16),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_address_type CHECK (address_type IN ('shipping', 'return'))
);

CREATE UNIQUE INDEX uq_order_address_order_type ON order_address (order_no, address_type) WHERE deleted_at IS NULL;
