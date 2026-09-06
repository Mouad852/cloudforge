CREATE TABLE products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    image_key   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
