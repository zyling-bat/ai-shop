CREATE TABLE shop (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    shop_no VARCHAR(32) NOT NULL,
    name VARCHAR(128) NOT NULL,
    logo TEXT,
    intro VARCHAR(500),
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    dsr_desc NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    dsr_service NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    dsr_logistics NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    main_category_id UUID,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    opened_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    extra JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_shop_status CHECK (status IN ('draft', 'applying', 'active', 'suspended', 'closed')),
    CONSTRAINT ck_shop_dsr_desc CHECK (dsr_desc >= 0 AND dsr_desc <= 5),
    CONSTRAINT ck_shop_dsr_service CHECK (dsr_service >= 0 AND dsr_service <= 5),
    CONSTRAINT ck_shop_dsr_logistics CHECK (dsr_logistics >= 0 AND dsr_logistics <= 5)
);

CREATE UNIQUE INDEX uq_shop_shop_no ON shop (shop_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_shop_merchant_id ON shop (merchant_id, status);
CREATE INDEX ix_shop_status_created_at ON shop (status, created_at DESC);
CREATE INDEX ix_shop_main_category_id ON shop (main_category_id);
