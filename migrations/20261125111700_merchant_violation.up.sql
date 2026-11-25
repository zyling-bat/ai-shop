CREATE TABLE merchant_violation (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    shop_id UUID,
    violation_type VARCHAR(32) NOT NULL,
    level VARCHAR(16) NOT NULL,
    title VARCHAR(128) NOT NULL,
    detail TEXT,
    evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
    penalty_type VARCHAR(32) NOT NULL DEFAULT 'none',
    penalty_amount NUMERIC(20,4),
    points_deduct INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'effective',
    effective_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    operator_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_violation_type CHECK (violation_type IN ('product', 'fake', 'price', 'service', 'logistics', 'fraud', 'other')),
    CONSTRAINT ck_merchant_violation_level CHECK (level IN ('warning', 'minor', 'major', 'severe')),
    CONSTRAINT ck_merchant_violation_penalty_type CHECK (penalty_type IN ('none', 'warning', 'points_deduct', 'suspend', 'close', 'confiscate')),
    CONSTRAINT ck_merchant_violation_penalty_amount CHECK (penalty_amount IS NULL OR penalty_amount >= 0),
    CONSTRAINT ck_merchant_violation_points_deduct CHECK (points_deduct >= 0),
    CONSTRAINT ck_merchant_violation_status CHECK (status IN ('effective', 'revoked', 'appealed'))
);

CREATE INDEX ix_merchant_violation_merchant_id ON merchant_violation (merchant_id, created_at DESC);
CREATE INDEX ix_merchant_violation_shop_id ON merchant_violation (shop_id, created_at DESC);
CREATE INDEX ix_merchant_violation_status ON merchant_violation (status, effective_at DESC);
