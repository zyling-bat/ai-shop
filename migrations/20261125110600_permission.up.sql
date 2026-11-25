CREATE TABLE permission (
    id UUID PRIMARY KEY,
    code VARCHAR(128) NOT NULL,
    name VARCHAR(64) NOT NULL,
    resource VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    description VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_permission_code ON permission (code) WHERE deleted_at IS NULL;
CREATE INDEX ix_permission_resource_action ON permission (resource, action);
