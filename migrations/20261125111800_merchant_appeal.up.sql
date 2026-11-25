CREATE TABLE merchant_appeal (
    id UUID PRIMARY KEY,
    appeal_no VARCHAR(32) NOT NULL,
    merchant_id UUID NOT NULL,
    violation_id UUID,
    appeal_type VARCHAR(32) NOT NULL,
    reason TEXT NOT NULL,
    evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
    status VARCHAR(32) NOT NULL DEFAULT 'submitted',
    result VARCHAR(255),
    handled_by UUID,
    handled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_appeal_type CHECK (appeal_type IN ('violation', 'qualification', 'settlement', 'other')),
    CONSTRAINT ck_merchant_appeal_status CHECK (status IN ('submitted', 'reviewing', 'approved', 'rejected', 'closed')),
    CONSTRAINT ck_merchant_appeal_violation CHECK (appeal_type <> 'violation' OR violation_id IS NOT NULL)
);

CREATE UNIQUE INDEX uq_merchant_appeal_appeal_no ON merchant_appeal (appeal_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_merchant_appeal_merchant_id ON merchant_appeal (merchant_id, status);
CREATE INDEX ix_merchant_appeal_violation_id ON merchant_appeal (violation_id);
