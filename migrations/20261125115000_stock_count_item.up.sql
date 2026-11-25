CREATE TABLE stock_count_item (
    id UUID PRIMARY KEY,
    count_no VARCHAR(32) NOT NULL,
    sku_id UUID NOT NULL,
    batch_no VARCHAR(64),
    book_qty INTEGER NOT NULL DEFAULT 0,
    actual_qty INTEGER NOT NULL DEFAULT 0,
    diff_qty INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT ck_stock_count_item_book_qty CHECK (book_qty >= 0),
    CONSTRAINT ck_stock_count_item_actual_qty CHECK (actual_qty >= 0),
    CONSTRAINT ck_stock_count_item_diff CHECK (diff_qty = actual_qty - book_qty)
);

CREATE UNIQUE INDEX uq_stock_count_item_no_sku_batch ON stock_count_item (count_no, sku_id, batch_no)
    NULLS NOT DISTINCT WHERE deleted_at IS NULL;
