CREATE TABLE supplier_sku (
    id UUID PRIMARY KEY,
    supplier_id UUID NOT NULL,
    sku_id UUID NOT NULL,
    supply_price NUMERIC(20,4) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    min_order_qty INTEGER NOT NULL DEFAULT 1,
    lead_time_days INTEGER NOT NULL DEFAULT 0,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_supplier_sku_supply_price CHECK (supply_price >= 0),
    CONSTRAINT ck_supplier_sku_min_order_qty CHECK (min_order_qty >= 1),
    CONSTRAINT ck_supplier_sku_lead_time_days CHECK (lead_time_days >= 0),
    CONSTRAINT ck_supplier_sku_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_supplier_sku_supplier_sku ON supplier_sku (supplier_id, sku_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_supplier_sku_primary ON supplier_sku (sku_id) WHERE is_primary AND deleted_at IS NULL;
CREATE INDEX ix_supplier_sku_sku_id ON supplier_sku (sku_id, status);
