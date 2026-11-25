CREATE TABLE staff_account (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    merchant_id UUID,
    shop_id UUID,
    dept VARCHAR(64),
    employee_no VARCHAR(64),
    is_primary BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_staff_account_scope CHECK (shop_id IS NULL OR merchant_id IS NOT NULL),
    CONSTRAINT ck_staff_account_status CHECK (status IN ('active', 'disabled'))
);

CREATE UNIQUE INDEX uq_staff_account_user_merchant_shop ON staff_account (user_id, merchant_id, shop_id) NULLS NOT DISTINCT WHERE deleted_at IS NULL;
CREATE INDEX ix_staff_account_merchant_id ON staff_account (merchant_id);
CREATE INDEX ix_staff_account_shop_id ON staff_account (shop_id);
