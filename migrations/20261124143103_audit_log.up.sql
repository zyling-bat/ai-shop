-- 请求审计：P0 只落请求元数据，业务审计字段随身份 / 交易域扩展（C30）。
CREATE TABLE audit_log (
    id UUID PRIMARY KEY,
    trace_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    method TEXT NOT NULL,
    path TEXT NOT NULL,
    status SMALLINT NOT NULL,
    latency_ms INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

COMMENT ON TABLE audit_log IS '请求审计：trace 串联与访问留痕';

CREATE INDEX idx_audit_log_trace_id ON audit_log (trace_id);
CREATE INDEX idx_audit_log_created_at ON audit_log (created_at DESC);
