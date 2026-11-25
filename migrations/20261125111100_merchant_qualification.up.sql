CREATE TABLE merchant_qualification (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    qual_type VARCHAR(32) NOT NULL,
    qual_no VARCHAR(128),
    qual_no_hash VARCHAR(64),
    file_url TEXT NOT NULL,
    valid_from DATE,
    valid_to DATE,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    reject_reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_merchant_qualification_type CHECK (qual_type IN ('business_license', 'legal_id', 'brand_auth', 'special_license', 'other')),
    CONSTRAINT ck_merchant_qualification_status CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    CONSTRAINT ck_merchant_qualification_period CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX uq_merchant_qualification_merchant_type ON merchant_qualification (merchant_id, qual_type)
    WHERE deleted_at IS NULL AND qual_type IN ('business_license', 'legal_id');
CREATE INDEX ix_merchant_qualification_merchant_id ON merchant_qualification (merchant_id, qual_type);
CREATE INDEX ix_merchant_qualification_status ON merchant_qualification (status, submitted_at DESC);
