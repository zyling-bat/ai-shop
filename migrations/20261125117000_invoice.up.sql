CREATE TABLE invoice (
    id UUID PRIMARY KEY,
    invoice_no VARCHAR(32) NOT NULL,
    order_no VARCHAR(32) NOT NULL,
    user_id UUID NOT NULL,
    invoice_type VARCHAR(16) NOT NULL DEFAULT 'personal',
    title VARCHAR(128) NOT NULL,
    tax_no VARCHAR(64),
    amount NUMERIC(20,4) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'applied',
    invoice_code VARCHAR(32),
    invoice_number VARCHAR(32),
    issued_at TIMESTAMPTZ,
    file_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_invoice_type CHECK (invoice_type IN ('personal', 'company')),
    CONSTRAINT ck_invoice_status CHECK (status IN ('applied', 'issued', 'failed', 'void')),
    CONSTRAINT ck_invoice_amount CHECK (amount >= 0)
);

CREATE UNIQUE INDEX uq_invoice_invoice_no ON invoice (invoice_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_invoice_order_no ON invoice (order_no);
CREATE INDEX ix_invoice_user_status ON invoice (user_id, status, created_at DESC);
