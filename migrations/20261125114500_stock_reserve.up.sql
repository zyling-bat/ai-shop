CREATE TABLE stock_reserve (
    id UUID PRIMARY KEY,
    reserve_no VARCHAR(32) NOT NULL,
    biz_type VARCHAR(16) NOT NULL,
    biz_no VARCHAR(64) NOT NULL,
    sku_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    qty INTEGER NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'reserved',
    expire_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_stock_reserve_biz_type CHECK (biz_type IN ('order', 'seckill', 'transfer')),
    CONSTRAINT ck_stock_reserve_qty CHECK (qty > 0),
    CONSTRAINT ck_stock_reserve_status CHECK (status IN ('reserved', 'confirmed', 'released'))
);

CREATE UNIQUE INDEX uq_stock_reserve_reserve_no ON stock_reserve (reserve_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_stock_reserve_biz ON stock_reserve (biz_no, sku_id, warehouse_id, status) WHERE deleted_at IS NULL;
CREATE INDEX ix_stock_reserve_expire_at ON stock_reserve (expire_at) WHERE status = 'reserved' AND deleted_at IS NULL;
