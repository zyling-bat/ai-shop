CREATE TABLE warehouse_zone (
    id UUID PRIMARY KEY,
    warehouse_id UUID NOT NULL,
    zone_no VARCHAR(32) NOT NULL,
    name VARCHAR(64) NOT NULL,
    region_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    priority INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_warehouse_zone_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_warehouse_zone_warehouse_zone_no ON warehouse_zone (warehouse_id, zone_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_warehouse_zone_warehouse_id ON warehouse_zone (warehouse_id, priority);
