-- 只增不改：订单状态迁移留痕。02 §2.15 的按月分区随 P4 并发压测统一改造。
CREATE TABLE order_status_log (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL,
    order_no VARCHAR(32) NOT NULL,
    from_status VARCHAR(24),
    to_status VARCHAR(24) NOT NULL,
    action VARCHAR(32) NOT NULL,
    operator_type VARCHAR(16) NOT NULL DEFAULT 'system',
    operator_id UUID,
    reason VARCHAR(255),
    trace_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_status_log_operator_type CHECK (
        operator_type IN ('user', 'merchant', 'platform', 'system')
    )
);

CREATE INDEX ix_order_status_log_order_no_created ON order_status_log (order_no, created_at);
CREATE INDEX ix_order_status_log_trace_id ON order_status_log (trace_id);
