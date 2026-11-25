CREATE TABLE merchant_contract (
    id UUID PRIMARY KEY,
    contract_no VARCHAR(64) NOT NULL,
    merchant_id UUID NOT NULL,
    contract_type VARCHAR(32) NOT NULL,
    start_at DATE NOT NULL,
    end_at DATE,
    signed_at DATE,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    commission_rate NUMERIC(10,6),
    settle_cycle VARCHAR(16),
    file_url TEXT,
    remark VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_contract_type CHECK (contract_type IN ('platform_service', 'settlement', 'supplement', 'other')),
    CONSTRAINT ck_merchant_contract_status CHECK (status IN ('draft', 'pending_sign', 'active', 'expired', 'terminated')),
    CONSTRAINT ck_merchant_contract_settle_cycle CHECK (settle_cycle IS NULL OR settle_cycle IN ('T+1', 'T+7')),
    CONSTRAINT ck_merchant_contract_commission_rate CHECK (commission_rate IS NULL OR (commission_rate >= 0 AND commission_rate <= 1)),
    CONSTRAINT ck_merchant_contract_period CHECK (end_at IS NULL OR end_at >= start_at)
);

CREATE UNIQUE INDEX uq_merchant_contract_contract_no ON merchant_contract (contract_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_merchant_contract_merchant_id ON merchant_contract (merchant_id, status);
CREATE INDEX ix_merchant_contract_end_at ON merchant_contract (end_at) WHERE end_at IS NOT NULL AND deleted_at IS NULL;
