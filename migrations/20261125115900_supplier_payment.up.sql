CREATE TABLE supplier_payment (
    id UUID PRIMARY KEY,
    payment_no VARCHAR(32) NOT NULL,
    supplier_id UUID NOT NULL,
    settlement_no VARCHAR(32),
    amount NUMERIC(20,4) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    pay_method VARCHAR(16) NOT NULL DEFAULT 'bank',
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    channel_txn_id VARCHAR(128),
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_supplier_payment_amount CHECK (amount > 0),
    CONSTRAINT ck_supplier_payment_method CHECK (pay_method IN ('bank', 'alipay', 'wechat', 'offset')),
    CONSTRAINT ck_supplier_payment_status CHECK (status IN ('pending', 'paying', 'success', 'failed'))
);

CREATE UNIQUE INDEX uq_supplier_payment_no ON supplier_payment (payment_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_supplier_payment_channel_txn ON supplier_payment (pay_method, channel_txn_id)
    WHERE channel_txn_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_supplier_payment_settlement_no ON supplier_payment (settlement_no) WHERE settlement_no IS NOT NULL AND deleted_at IS NULL;
