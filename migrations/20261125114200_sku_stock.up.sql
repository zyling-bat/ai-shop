CREATE TABLE sku_stock (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    available_qty INTEGER NOT NULL DEFAULT 0,
    locked_qty INTEGER NOT NULL DEFAULT 0,
    occupied_qty INTEGER NOT NULL DEFAULT 0,
    safety_qty INTEGER NOT NULL DEFAULT 0,
    version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_sku_stock_available_qty CHECK (available_qty >= 0),
    CONSTRAINT ck_sku_stock_locked_qty CHECK (locked_qty >= 0),
    CONSTRAINT ck_sku_stock_occupied_qty CHECK (occupied_qty >= 0),
    CONSTRAINT ck_sku_stock_safety_qty CHECK (safety_qty >= 0),
    CONSTRAINT ck_sku_stock_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_sku_stock_sku_warehouse ON sku_stock (sku_id, warehouse_id) WHERE deleted_at IS NULL;
