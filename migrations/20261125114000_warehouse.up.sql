CREATE TABLE warehouse (
    id UUID PRIMARY KEY,
    warehouse_no VARCHAR(32) NOT NULL,
    merchant_id UUID NOT NULL,
    name VARCHAR(64) NOT NULL,
    type VARCHAR(16) NOT NULL DEFAULT 'normal',
    province VARCHAR(64),
    city VARCHAR(64),
    district VARCHAR(64),
    address VARCHAR(255),
    contact_name VARCHAR(64),
    contact_phone VARCHAR(32),
    is_default BOOLEAN NOT NULL DEFAULT false,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_warehouse_type CHECK (type IN ('normal', 'bonded', 'virtual')),
    CONSTRAINT ck_warehouse_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_warehouse_no ON warehouse (warehouse_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_warehouse_default ON warehouse (merchant_id) WHERE is_default AND deleted_at IS NULL;
CREATE INDEX ix_warehouse_merchant_id ON warehouse (merchant_id, status);
