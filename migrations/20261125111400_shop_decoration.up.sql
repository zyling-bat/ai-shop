CREATE TABLE shop_decoration (
    id UUID PRIMARY KEY,
    shop_id UUID NOT NULL,
    page VARCHAR(32) NOT NULL DEFAULT 'home',
    version INTEGER NOT NULL DEFAULT 1,
    layout JSONB NOT NULL DEFAULT '{}'::jsonb,
    theme JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_published BOOLEAN NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_shop_decoration_page CHECK (page IN ('home', 'category', 'custom')),
    CONSTRAINT ck_shop_decoration_version CHECK (version >= 1)
);

CREATE UNIQUE INDEX uq_shop_decoration_shop_page_version ON shop_decoration (shop_id, page, version) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_shop_decoration_published ON shop_decoration (shop_id, page) WHERE deleted_at IS NULL AND is_published;
CREATE INDEX ix_shop_decoration_shop_id ON shop_decoration (shop_id, page);
