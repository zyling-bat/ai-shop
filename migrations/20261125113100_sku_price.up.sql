CREATE TABLE sku_price (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    price_type VARCHAR(16) NOT NULL,
    price_amount NUMERIC(20,4) NOT NULL,
    min_qty INTEGER NOT NULL DEFAULT 1,
    max_qty INTEGER,
    region_code VARCHAR(16),
    start_at TIMESTAMPTZ,
    end_at TIMESTAMPTZ,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_sku_price_type CHECK (price_type IN ('list', 'sale', 'member', 'tier', 'activity', 'region')),
    CONSTRAINT ck_sku_price_amount CHECK (price_amount >= 0),
    CONSTRAINT ck_sku_price_min_qty CHECK (min_qty >= 1),
    CONSTRAINT ck_sku_price_max_qty CHECK (max_qty IS NULL OR max_qty >= min_qty),
    CONSTRAINT ck_sku_price_period CHECK (end_at IS NULL OR start_at IS NULL OR end_at >= start_at),
    CONSTRAINT ck_sku_price_status CHECK (status IN ('active', 'disabled'))
);

CREATE INDEX ix_sku_price_sku_type_start ON sku_price (sku_id, price_type, start_at);
CREATE UNIQUE INDEX uq_sku_price_sku_type_region_start ON sku_price (sku_id, price_type, region_code, start_at)
    NULLS NOT DISTINCT WHERE deleted_at IS NULL;
