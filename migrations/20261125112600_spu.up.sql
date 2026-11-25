CREATE TABLE spu (
    id UUID PRIMARY KEY,
    spu_no VARCHAR(32) NOT NULL,
    merchant_id UUID NOT NULL,
    shop_id UUID NOT NULL,
    category_id UUID NOT NULL,
    brand_id UUID,
    title VARCHAR(255) NOT NULL,
    sub_title VARCHAR(255),
    main_image TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    audit_status VARCHAR(32) NOT NULL DEFAULT 'none',
    is_self_support BOOLEAN NOT NULL DEFAULT false,
    sale_channel JSONB NOT NULL DEFAULT '["web","h5","miniapp","app"]'::jsonb,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_spu_status CHECK (status IN ('draft', 'pending', 'on_sale', 'off_sale', 'banned')),
    CONSTRAINT ck_spu_audit_status CHECK (audit_status IN ('none', 'pending', 'machine_reviewing', 'human_reviewing', 'approved', 'rejected', 'need_supplement'))
);

CREATE UNIQUE INDEX uq_spu_spu_no ON spu (spu_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_spu_shop_status ON spu (shop_id, status, created_at DESC);
CREATE INDEX ix_spu_merchant_id ON spu (merchant_id, status);
CREATE INDEX ix_spu_category_id ON spu (category_id, status, sort_weight DESC);
CREATE INDEX ix_spu_brand_id ON spu (brand_id);
CREATE INDEX ix_spu_audit_status ON spu (audit_status, created_at DESC);
