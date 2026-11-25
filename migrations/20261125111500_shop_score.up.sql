CREATE TABLE shop_score (
    id UUID PRIMARY KEY,
    shop_id UUID NOT NULL,
    stat_date DATE NOT NULL,
    dsr_desc NUMERIC(3,2) NOT NULL DEFAULT 0,
    dsr_service NUMERIC(3,2) NOT NULL DEFAULT 0,
    dsr_logistics NUMERIC(3,2) NOT NULL DEFAULT 0,
    review_count INTEGER NOT NULL DEFAULT 0,
    good_rate NUMERIC(10,6) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_shop_score_dsr_desc CHECK (dsr_desc >= 0 AND dsr_desc <= 5),
    CONSTRAINT ck_shop_score_dsr_service CHECK (dsr_service >= 0 AND dsr_service <= 5),
    CONSTRAINT ck_shop_score_dsr_logistics CHECK (dsr_logistics >= 0 AND dsr_logistics <= 5),
    CONSTRAINT ck_shop_score_review_count CHECK (review_count >= 0),
    CONSTRAINT ck_shop_score_good_rate CHECK (good_rate >= 0 AND good_rate <= 1)
);

CREATE UNIQUE INDEX uq_shop_score_shop_date ON shop_score (shop_id, stat_date) WHERE deleted_at IS NULL;
CREATE INDEX ix_shop_score_stat_date ON shop_score (stat_date);
