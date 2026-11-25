CREATE TABLE sku_media (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    media_type VARCHAR(16) NOT NULL DEFAULT 'image',
    url TEXT NOT NULL,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    is_main BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_sku_media_type CHECK (media_type IN ('image', 'video'))
);

CREATE UNIQUE INDEX uq_sku_media_main ON sku_media (sku_id) WHERE is_main AND deleted_at IS NULL;
CREATE INDEX ix_sku_media_sku_id ON sku_media (sku_id, sort_weight);
