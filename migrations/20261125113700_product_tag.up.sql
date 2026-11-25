CREATE TABLE product_tag (
    id UUID PRIMARY KEY,
    spu_id UUID NOT NULL,
    tag_code VARCHAR(32) NOT NULL,
    tag_name VARCHAR(64) NOT NULL,
    source VARCHAR(16) NOT NULL DEFAULT 'merchant',
    sort_weight INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_tag_source CHECK (source IN ('merchant', 'platform', 'ai'))
);

CREATE UNIQUE INDEX uq_product_tag_spu_tag ON product_tag (spu_id, tag_code) WHERE deleted_at IS NULL;
CREATE INDEX ix_product_tag_tag_code ON product_tag (tag_code, spu_id);
