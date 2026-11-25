CREATE TABLE sku_stock_batch (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    batch_no VARCHAR(64) NOT NULL,
    production_at DATE,
    expire_at DATE,
    qty INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'normal',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_sku_stock_batch_qty CHECK (qty >= 0),
    CONSTRAINT ck_sku_stock_batch_period CHECK (production_at IS NULL OR expire_at IS NULL OR expire_at >= production_at),
    CONSTRAINT ck_sku_stock_batch_status CHECK (status IN ('normal', 'frozen', 'expired'))
);

CREATE UNIQUE INDEX uq_sku_stock_batch_sku_warehouse_batch ON sku_stock_batch (sku_id, warehouse_id, batch_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_sku_stock_batch_expire_at ON sku_stock_batch (expire_at) WHERE expire_at IS NOT NULL AND deleted_at IS NULL;
