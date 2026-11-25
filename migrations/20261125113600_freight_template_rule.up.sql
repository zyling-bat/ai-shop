CREATE TABLE freight_template_rule (
    id UUID PRIMARY KEY,
    template_id UUID NOT NULL,
    region_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    first_qty NUMERIC(20,4) NOT NULL DEFAULT 1,
    first_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    extra_qty NUMERIC(20,4) NOT NULL DEFAULT 1,
    extra_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    is_free BOOLEAN NOT NULL DEFAULT false,
    sort_weight INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_freight_template_rule_first_qty CHECK (first_qty > 0),
    CONSTRAINT ck_freight_template_rule_first_amount CHECK (first_amount >= 0),
    CONSTRAINT ck_freight_template_rule_extra_qty CHECK (extra_qty > 0),
    CONSTRAINT ck_freight_template_rule_extra_amount CHECK (extra_amount >= 0)
);

CREATE INDEX ix_freight_template_rule_template_id ON freight_template_rule (template_id, sort_weight);
