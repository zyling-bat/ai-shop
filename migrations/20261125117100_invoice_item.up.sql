CREATE TABLE invoice_item (
    id UUID PRIMARY KEY,
    invoice_id UUID NOT NULL,
    order_no VARCHAR(32) NOT NULL,
    order_item_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    amount NUMERIC(20,4) NOT NULL,
    tax_rate NUMERIC(10,6) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_invoice_item_amount CHECK (amount >= 0 AND tax_amount >= 0),
    CONSTRAINT ck_invoice_item_tax_rate CHECK (tax_rate >= 0 AND tax_rate <= 1)
);

CREATE UNIQUE INDEX uq_invoice_item_invoice_order_item ON invoice_item (invoice_id, order_item_id) WHERE deleted_at IS NULL;
