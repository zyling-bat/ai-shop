CREATE TABLE stock_log (
    id UUID PRIMARY KEY,
    sku_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    change_type VARCHAR(16) NOT NULL,
    delta_available INTEGER NOT NULL DEFAULT 0,
    delta_locked INTEGER NOT NULL DEFAULT 0,
    delta_occupied INTEGER NOT NULL DEFAULT 0,
    biz_no VARCHAR(64),
    operator_id UUID,
    remark VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_stock_log_change_type CHECK (change_type IN ('inbound', 'outbound', 'reserve', 'confirm', 'release', 'adjust', 'count', 'transfer'))
);

CREATE INDEX ix_stock_log_sku_warehouse_created ON stock_log (sku_id, warehouse_id, created_at DESC);
CREATE INDEX ix_stock_log_biz_no ON stock_log (biz_no) WHERE biz_no IS NOT NULL AND deleted_at IS NULL;
