CREATE TABLE deposit_record (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL,
    merchant_id UUID NOT NULL,
    record_no VARCHAR(64) NOT NULL,
    direction VARCHAR(8) NOT NULL,
    amount NUMERIC(20,4) NOT NULL,
    balance_after NUMERIC(20,4) NOT NULL,
    biz_type VARCHAR(32) NOT NULL,
    biz_ref VARCHAR(64),
    status VARCHAR(32) NOT NULL DEFAULT 'success',
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    remark VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_deposit_record_direction CHECK (direction IN ('in', 'out')),
    CONSTRAINT ck_deposit_record_amount CHECK (amount > 0),
    CONSTRAINT ck_deposit_record_balance_after CHECK (balance_after >= 0),
    CONSTRAINT ck_deposit_record_biz_type CHECK (biz_type IN ('recharge', 'deduct', 'refund', 'freeze', 'unfreeze', 'adjust')),
    CONSTRAINT ck_deposit_record_status CHECK (status IN ('pending', 'success', 'failed'))
);

CREATE UNIQUE INDEX uq_deposit_record_record_no ON deposit_record (record_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_deposit_record_merchant_id ON deposit_record (merchant_id, occurred_at DESC);
CREATE INDEX ix_deposit_record_account_id ON deposit_record (account_id, occurred_at DESC);
