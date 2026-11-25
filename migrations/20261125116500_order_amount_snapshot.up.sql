-- 只增不改：金额计算留痕，用于复现下单时的价格结果。
CREATE TABLE order_amount_snapshot (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL,
    calc_version VARCHAR(32) NOT NULL,
    input JSONB NOT NULL,
    output JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_order_amount_snapshot_order_no ON order_amount_snapshot (order_no) WHERE deleted_at IS NULL;
