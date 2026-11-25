CREATE TABLE deposit_account (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    balance_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    frozen_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    last_txn_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_deposit_account_balance_amount CHECK (balance_amount >= 0),
    CONSTRAINT ck_deposit_account_frozen_amount CHECK (frozen_amount >= 0),
    CONSTRAINT ck_deposit_account_frozen_le_balance CHECK (frozen_amount <= balance_amount)
);

CREATE UNIQUE INDEX uq_deposit_account_merchant_id ON deposit_account (merchant_id) WHERE deleted_at IS NULL;
