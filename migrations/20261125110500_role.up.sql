CREATE TABLE role (
    id UUID PRIMARY KEY,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(64) NOT NULL,
    scope VARCHAR(16) NOT NULL,
    description VARCHAR(255),
    is_system BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_role_scope CHECK (scope IN ('platform', 'merchant', 'shop')),
    CONSTRAINT ck_role_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_role_code ON role (code) WHERE deleted_at IS NULL;
CREATE INDEX ix_role_scope_status ON role (scope, status);
