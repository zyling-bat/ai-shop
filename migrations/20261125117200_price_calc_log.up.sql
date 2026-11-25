-- 只增不改：价格计算留痕，用于复现。
CREATE TABLE price_calc_log (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32),
    user_id UUID NOT NULL,
    calc_type VARCHAR(16) NOT NULL DEFAULT 'order',
    engine_version VARCHAR(32) NOT NULL,
    input JSONB NOT NULL,
    output JSONB NOT NULL,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    trace_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_price_calc_log_type CHECK (calc_type IN ('cart', 'order', 'preview')),
    CONSTRAINT ck_price_calc_log_duration CHECK (duration_ms >= 0)
);

CREATE INDEX ix_price_calc_log_order_no ON price_calc_log (order_no) WHERE order_no IS NOT NULL;
CREATE INDEX ix_price_calc_log_user_created ON price_calc_log (user_id, created_at DESC);
