-- Findaro commercial: clientes, órdenes, tokens de descarga, contador promo
CREATE TABLE IF NOT EXISTS customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  amount_usd            NUMERIC(10,2) NOT NULL,
  currency              TEXT NOT NULL DEFAULT 'usd',
  status                TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  stripe_session_id     TEXT UNIQUE,
  stripe_payment_intent TEXT,
  promo_slot            BOOLEAN NOT NULL DEFAULT false,
  product_version       TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at               TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS orders_status_idx ON orders (status);
CREATE INDEX IF NOT EXISTS orders_customer_idx ON orders (customer_id);

CREATE TABLE IF NOT EXISTS download_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  token         TEXT NOT NULL UNIQUE,
  expires_at    TIMESTAMPTZ NOT NULL,
  used_count    INT NOT NULL DEFAULT 0,
  max_uses      INT NOT NULL DEFAULT 10,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS download_tokens_token_idx ON download_tokens (token);

CREATE TABLE IF NOT EXISTS promo_state (
  id            INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  sold_count    INT NOT NULL DEFAULT 0,
  promo_limit   INT NOT NULL DEFAULT 1000,
  promo_price   NUMERIC(10,2) NOT NULL DEFAULT 59.00,
  regular_price NUMERIC(10,2) NOT NULL DEFAULT 99.00,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO promo_state (id, sold_count)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;
