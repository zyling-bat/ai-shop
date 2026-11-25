CREATE TABLE sku (
    id UUID PRIMARY KEY,
    sku_no VARCHAR(32) NOT NULL,
    spu_id UUID NOT NULL,
    barcode VARCHAR(64),
    spec_values JSONB NOT NULL DEFAULT '{}'::jsonb,
    image TEXT,
    weight_g INTEGER,
    volume_cm3 INTEGER,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_sku_status CHECK (status IN ('draft', 'on_sale', 'off_sale', 'banned')),
    CONSTRAINT ck_sku_weight_g CHECK (weight_g IS NULL OR weight_g >= 0),
    CONSTRAINT ck_sku_volume_cm3 CHECK (volume_cm3 IS NULL OR volume_cm3 >= 0),
    CONSTRAINT ck_sku_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_sku_sku_no ON sku (sku_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_sku_spu_barcode ON sku (spu_id, barcode) WHERE barcode IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_sku_spu_id ON sku (spu_id, status);
CREATE INDEX ix_sku_barcode ON sku (barcode) WHERE barcode IS NOT NULL AND deleted_at IS NULL;
