CREATE TABLE order_remark (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL,
    remark_type VARCHAR(16) NOT NULL DEFAULT 'user',
    content TEXT NOT NULL,
    operator_id UUID,
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_remark_type CHECK (remark_type IN ('user', 'merchant', 'platform'))
);

CREATE INDEX ix_order_remark_order_no ON order_remark (order_no, created_at DESC);
