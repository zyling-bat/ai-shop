-- order 是 PostgreSQL 保留字，全部写作 "order"。
CREATE TABLE "order" (
    id UUID PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL,
    user_id UUID NOT NULL,
    merchant_id UUID NOT NULL,
    shop_id UUID NOT NULL,
    order_type VARCHAR(16) NOT NULL DEFAULT 'normal',
    status VARCHAR(24) NOT NULL DEFAULT 'created',
    pay_status VARCHAR(16) NOT NULL DEFAULT 'unpaid',
    ship_status VARCHAR(16) NOT NULL DEFAULT 'unshipped',
    after_sale_status VARCHAR(16) NOT NULL DEFAULT 'none',
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    goods_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    freight_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    payable_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(20,4) NOT NULL DEFAULT 0,
    snapshot_id UUID,
    channel VARCHAR(16) NOT NULL DEFAULT 'web',
    source JSONB NOT NULL DEFAULT '{}'::jsonb,
    parent_order_no VARCHAR(32),
    pay_expire_at TIMESTAMPTZ,
    auto_receive_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_order_order_type CHECK (
        order_type IN ('normal', 'presale', 'seckill', 'groupbuy', 'virtual', 'service')
    ),
    CONSTRAINT ck_order_status CHECK (
        status IN (
            'created', 'pending_pay', 'paid', 'partially_shipped', 'shipped',
            'received', 'after_sale', 'completed', 'cancelled', 'closed'
        )
    ),
    CONSTRAINT ck_order_pay_status CHECK (
        pay_status IN ('unpaid', 'paying', 'paid', 'refunding', 'refunded', 'closed')
    ),
    CONSTRAINT ck_order_ship_status CHECK (
        ship_status IN ('unshipped', 'partial_shipped', 'shipped', 'received')
    ),
    CONSTRAINT ck_order_after_sale_status CHECK (
        after_sale_status IN ('none', 'applying', 'processing', 'finished')
    ),
    CONSTRAINT ck_order_channel CHECK (
        channel IN ('web', 'h5', 'miniapp', 'app', 'open', 'api')
    ),
    CONSTRAINT ck_order_amounts_non_negative CHECK (
        goods_amount >= 0
        AND discount_amount >= 0
        AND freight_amount >= 0
        AND tax_amount >= 0
        AND payable_amount >= 0
        AND paid_amount >= 0
    )
);

CREATE UNIQUE INDEX uq_order_order_no ON "order" (order_no) WHERE deleted_at IS NULL;
CREATE INDEX ix_order_user_status_created ON "order" (user_id, status, created_at DESC);
CREATE INDEX ix_order_merchant_status_created ON "order" (merchant_id, status, created_at DESC);
CREATE INDEX ix_order_shop_status_created ON "order" (shop_id, status, created_at DESC);
CREATE INDEX ix_order_pay_expire ON "order" (pay_expire_at) WHERE status = 'pending_pay';
CREATE INDEX ix_order_parent_order_no ON "order" (parent_order_no);
