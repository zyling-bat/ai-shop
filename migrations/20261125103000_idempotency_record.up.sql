-- 幂等记录：所有写接口按 (scope, key) 幂等（C14），契约见 02 §2.14。
CREATE TABLE idempotency_record (
    id UUID PRIMARY KEY,
    scope VARCHAR(64) NOT NULL,
    key VARCHAR(128) NOT NULL,
    request_hash CHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,
    response JSONB,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_idempotency_record_status
        CHECK (status IN ('processing', 'done', 'failed'))
);

COMMENT ON TABLE idempotency_record IS '写接口幂等记录：同 key 同指纹返回首次结果';

CREATE UNIQUE INDEX uq_idempotency_record_scope_key
    ON idempotency_record (scope, key)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_idempotency_record_expires_at
    ON idempotency_record (expires_at);
