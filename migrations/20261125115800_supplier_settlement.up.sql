CREATE TABLE supplier_settlement (
    id UUID PRIMARY KEY,
    settlement_no VARCHAR(32) NOT NULL,
    supplier_id UUID NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    return_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    net_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'generated',
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_supplier_settlement_period CHECK (period_end >= period_start),
    CONSTRAINT ck_supplier_settlement_gross_amount CHECK (gross_amount >= 0),
    CONSTRAINT ck_supplier_settlement_return_amount CHECK (return_amount >= 0),
    CONSTRAINT ck_supplier_settlement_net_amount CHECK (net_amount = gross_amount - return_amount),
    CONSTRAINT ck_supplier_settlement_status CHECK (status IN ('generated', 'confirmed', 'paying', 'paid', 'closed'))
);

CREATE UNIQUE INDEX uq_supplier_settlement_no ON supplier_settlement (settlement_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_supplier_settlement_supplier_period ON supplier_settlement (supplier_id, period_start, period_end) WHERE deleted_at IS NULL;
