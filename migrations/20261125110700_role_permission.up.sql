CREATE TABLE role_permission (
    id UUID PRIMARY KEY,
    role_id UUID NOT NULL,
    permission_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_role_permission_role_permission ON role_permission (role_id, permission_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_role_permission_permission_id ON role_permission (permission_id);
