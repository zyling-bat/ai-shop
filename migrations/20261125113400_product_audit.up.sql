CREATE TABLE product_audit (
    id UUID PRIMARY KEY,
    target_type VARCHAR(16) NOT NULL,
    target_id UUID NOT NULL,
    round SMALLINT NOT NULL DEFAULT 1,
    status VARCHAR(32) NOT NULL DEFAULT 'submitted',
    result VARCHAR(16),
    reason_code VARCHAR(64),
    reviewer_id UUID,
    machine_score NUMERIC(5,2),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_audit_target_type CHECK (target_type IN ('spu', 'media', 'detail')),
    CONSTRAINT ck_product_audit_status CHECK (status IN ('submitted', 'machine_reviewing', 'human_reviewing', 'approved', 'rejected', 'need_supplement')),
    CONSTRAINT ck_product_audit_result CHECK (result IS NULL OR result IN ('approved', 'rejected', 'need_supplement')),
    CONSTRAINT ck_product_audit_round CHECK (round >= 1),
    CONSTRAINT ck_product_audit_machine_score CHECK (machine_score IS NULL OR (machine_score >= 0 AND machine_score <= 100))
);

CREATE UNIQUE INDEX uq_product_audit_target_round ON product_audit (target_type, target_id, round) WHERE deleted_at IS NULL;
CREATE INDEX ix_product_audit_target ON product_audit (target_type, target_id, created_at DESC);
CREATE INDEX ix_product_audit_status ON product_audit (status, created_at);
