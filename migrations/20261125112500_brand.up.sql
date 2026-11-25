CREATE TABLE brand (
    id UUID PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    name_en VARCHAR(64),
    first_letter CHAR(1),
    logo TEXT,
    description VARCHAR(255),
    sort_weight INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_brand_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_brand_name ON brand (name) WHERE deleted_at IS NULL;
CREATE INDEX ix_brand_first_letter ON brand (first_letter, sort_weight);
