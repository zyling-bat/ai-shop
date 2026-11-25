CREATE TABLE stock_count (
    id UUID PRIMARY KEY,
    count_no VARCHAR(32) NOT NULL,
    warehouse_id UUID NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'created',
    count_type VARCHAR(16) NOT NULL DEFAULT 'full',
    operator_id UUID,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    remark VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_stock_count_status CHECK (status IN ('created', 'counting', 'submitted', 'reviewed', 'adjusted', 'closed')),
    CONSTRAINT ck_stock_count_type CHECK (count_type IN ('full', 'partial'))
);

CREATE UNIQUE INDEX uq_stock_count_no ON stock_count (count_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_stock_count_warehouse_id ON stock_count (warehouse_id, status);
