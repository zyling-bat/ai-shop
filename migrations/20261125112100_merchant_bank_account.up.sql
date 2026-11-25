CREATE TABLE merchant_bank_account (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    account_no_enc TEXT NOT NULL,
    account_no_hash VARCHAR(64) NOT NULL,
    account_no_last4 CHAR(4) NOT NULL,
    bank_name VARCHAR(128) NOT NULL,
    bank_branch VARCHAR(128),
    holder VARCHAR(64) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_bank_account_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_merchant_bank_account_no ON merchant_bank_account (account_no_hash) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_merchant_bank_account_default ON merchant_bank_account (merchant_id) WHERE deleted_at IS NULL AND is_default;
CREATE INDEX ix_merchant_bank_account_merchant_id ON merchant_bank_account (merchant_id, status);
