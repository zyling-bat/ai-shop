CREATE TABLE product_detail (
    id UUID PRIMARY KEY,
    spu_id UUID NOT NULL,
    content JSONB NOT NULL DEFAULT '{}'::jsonb,
    content_html TEXT,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_detail_version CHECK (version >= 1)
);

CREATE UNIQUE INDEX uq_product_detail_spu_id ON product_detail (spu_id) WHERE deleted_at IS NULL;
