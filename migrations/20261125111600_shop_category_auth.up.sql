CREATE TABLE shop_category_auth (
    id UUID PRIMARY KEY,
    shop_id UUID NOT NULL,
    category_id UUID NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    source VARCHAR(32) NOT NULL DEFAULT 'apply',
    rate NUMERIC(10,6),
    valid_from DATE,
    valid_to DATE,
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    reject_reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_shop_category_auth_status CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'revoked')),
    CONSTRAINT ck_shop_category_auth_source CHECK (source IN ('apply', 'platform_grant')),
    CONSTRAINT ck_shop_category_auth_rate CHECK (rate IS NULL OR (rate >= 0 AND rate <= 1)),
    CONSTRAINT ck_shop_category_auth_period CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX uq_shop_category_auth_shop_category ON shop_category_auth (shop_id, category_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_shop_category_auth_category_id ON shop_category_auth (category_id, status);
CREATE INDEX ix_shop_category_auth_valid_to ON shop_category_auth (valid_to) WHERE valid_to IS NOT NULL AND deleted_at IS NULL;
