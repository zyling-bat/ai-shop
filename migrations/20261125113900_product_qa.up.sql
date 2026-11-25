CREATE TABLE product_qa (
    id UUID PRIMARY KEY,
    spu_id UUID NOT NULL,
    user_id UUID,
    question TEXT NOT NULL,
    answer TEXT,
    source VARCHAR(16) NOT NULL DEFAULT 'user',
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    answered_by UUID,
    answered_at TIMESTAMPTZ,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_product_qa_source CHECK (source IN ('user', 'merchant', 'ai')),
    CONSTRAINT ck_product_qa_status CHECK (status IN ('pending', 'answered', 'closed'))
);

CREATE INDEX ix_product_qa_spu_id ON product_qa (spu_id, is_pinned DESC, created_at DESC);
CREATE INDEX ix_product_qa_status ON product_qa (status, created_at);
