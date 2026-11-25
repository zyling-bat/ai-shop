CREATE TABLE product_limit (
    id UUID PRIMARY KEY,
    scope VARCHAR(16) NOT NULL,
    target_id UUID NOT NULL,
    limit_type VARCHAR(16) NOT NULL,
    limit_qty INTEGER NOT NULL,
    start_at TIMESTAMPTZ,
    end_at TIMESTAMPTZ,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_limit_scope CHECK (scope IN ('sku', 'spu', 'category', 'activity')),
    CONSTRAINT ck_product_limit_type CHECK (limit_type IN ('per_user', 'per_order', 'per_day')),
    CONSTRAINT ck_product_limit_qty CHECK (limit_qty >= 1),
    CONSTRAINT ck_product_limit_period CHECK (end_at IS NULL OR start_at IS NULL OR end_at >= start_at),
    CONSTRAINT ck_product_limit_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_product_limit_scope_target_type ON product_limit (scope, target_id, limit_type) WHERE deleted_at IS NULL;
CREATE INDEX ix_product_limit_target_id ON product_limit (target_id, status);
