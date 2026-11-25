CREATE TABLE freight_template (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    name VARCHAR(64) NOT NULL,
    charge_type VARCHAR(16) NOT NULL DEFAULT 'piece',
    is_free BOOLEAN NOT NULL DEFAULT false,
    free_threshold_amount NUMERIC(20,4),
    is_default BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_freight_template_charge_type CHECK (charge_type IN ('weight', 'piece', 'volume', 'amount')),
    CONSTRAINT ck_freight_template_free_threshold CHECK (free_threshold_amount IS NULL OR free_threshold_amount >= 0),
    CONSTRAINT ck_freight_template_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_freight_template_merchant_name ON freight_template (merchant_id, name) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_freight_template_default ON freight_template (merchant_id) WHERE is_default AND deleted_at IS NULL;
CREATE INDEX ix_freight_template_merchant_id ON freight_template (merchant_id, status);
