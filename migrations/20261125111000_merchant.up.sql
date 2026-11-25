CREATE TABLE merchant (
    id UUID PRIMARY KEY,
    merchant_no VARCHAR(32) NOT NULL,
    name VARCHAR(128) NOT NULL,
    type VARCHAR(16) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'applying',
    commission_rate NUMERIC(10,6) NOT NULL DEFAULT 0,
    settle_cycle VARCHAR(16) NOT NULL DEFAULT 'T+1',
    contact_name VARCHAR(64),
    contact_phone_hash VARCHAR(64),
    contact_phone_enc TEXT,
    email_hash VARCHAR(64),
    email_enc TEXT,
    province VARCHAR(64),
    city VARCHAR(64),
    district VARCHAR(64),
    address VARCHAR(255),
    applied_at TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    suspended_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    extra JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_type CHECK (type IN ('personal', 'company')),
    CONSTRAINT ck_merchant_status CHECK (status IN ('applying', 'active', 'suspended', 'closed')),
    CONSTRAINT ck_merchant_settle_cycle CHECK (settle_cycle IN ('T+1', 'T+7')),
    CONSTRAINT ck_merchant_commission_rate CHECK (commission_rate >= 0 AND commission_rate <= 1)
);

CREATE UNIQUE INDEX uq_merchant_merchant_no ON merchant (merchant_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_merchant_status_created_at ON merchant (status, created_at DESC);
CREATE INDEX ix_merchant_type_status ON merchant (type, status);
