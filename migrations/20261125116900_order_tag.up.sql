CREATE TABLE order_tag (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL,
    tag_code VARCHAR(32) NOT NULL,
    tag_name VARCHAR(64),
    source VARCHAR(16) NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_tag_source CHECK (source IN ('manual', 'rule', 'ai'))
);

CREATE UNIQUE INDEX uq_order_tag_order_tag ON order_tag (order_no, tag_code) WHERE deleted_at IS NULL;
CREATE INDEX ix_order_tag_tag_code ON order_tag (tag_code, created_at DESC);
