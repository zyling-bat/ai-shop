CREATE TABLE supplier (
    id UUID PRIMARY KEY,
    supplier_no VARCHAR(32) NOT NULL,
    merchant_id UUID NOT NULL,
    name VARCHAR(128) NOT NULL,
    type VARCHAR(16) NOT NULL DEFAULT 'company',
    contact_name VARCHAR(64),
    contact_phone VARCHAR(32),
    address VARCHAR(255),
    settle_cycle VARCHAR(16) NOT NULL DEFAULT 'T+1',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_supplier_type CHECK (type IN ('personal', 'company')),
    CONSTRAINT ck_supplier_settle_cycle CHECK (settle_cycle IN ('T+1', 'T+7', 'T+15', 'T+30')),
    CONSTRAINT ck_supplier_status CHECK (status IN ('applying', 'active', 'suspended', 'closed'))
);

CREATE UNIQUE INDEX uq_supplier_no ON supplier (supplier_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_supplier_merchant_id ON supplier (merchant_id, status);
