CREATE TABLE product_media (
    id UUID PRIMARY KEY,
    spu_id UUID NOT NULL,
    media_type VARCHAR(16) NOT NULL DEFAULT 'image',
    url TEXT NOT NULL,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    is_main BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_media_type CHECK (media_type IN ('image', 'video'))
);

CREATE UNIQUE INDEX uq_product_media_main ON product_media (spu_id) WHERE is_main AND deleted_at IS NULL;
CREATE INDEX ix_product_media_spu_id ON product_media (spu_id, sort_weight);
