-- 事务消息：业务数据与事件同事务写入，worker 投递（C18 / ADR-004），契约见 02 §2.14。
CREATE TABLE outbox_event (
    id UUID PRIMARY KEY,
    event_id UUID NOT NULL,
    aggregate_type VARCHAR(64) NOT NULL,
    aggregate_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(128) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    retry_count SMALLINT NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_outbox_event_status
        CHECK (status IN ('pending', 'sent', 'failed', 'dead')),
    CONSTRAINT ck_outbox_event_retry_count
        CHECK (retry_count >= 0)
);

COMMENT ON TABLE outbox_event IS '事务消息 outbox：同事务写入、worker 投递、消费端按 event_id 幂等';

CREATE UNIQUE INDEX uq_outbox_event_event_id
    ON outbox_event (event_id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_outbox_event_status_next_retry_at
    ON outbox_event (status, next_retry_at);
