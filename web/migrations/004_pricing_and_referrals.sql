-- 004_pricing_and_referrals.sql
-- Nuevos precios: $39 USD (Personal, 2 Macs) / $59 USD (Familiar, 5 Macs)
-- Activaciones multi-Mac y programa de referidos con cashback de $10 USD por amigo

ALTER TABLE licenses ALTER COLUMN seats SET DEFAULT 2;
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'personal';

CREATE TABLE IF NOT EXISTS license_activations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  license_id    UUID NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  machine_id    TEXT NOT NULL,
  machine_name  TEXT NOT NULL DEFAULT '',
  activated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (license_id, machine_id)
);

CREATE INDEX IF NOT EXISTS lic_activations_lic_idx ON license_activations (license_id);
CREATE INDEX IF NOT EXISTS lic_activations_machine_idx ON license_activations (machine_id);

-- Migrar machine_id previo si existe
INSERT INTO license_activations (license_id, machine_id, machine_name, activated_at)
SELECT id, machine_id, 'Mac Principal', COALESCE(activated_at, now())
FROM licenses
WHERE machine_id IS NOT NULL AND machine_id != ''
ON CONFLICT (license_id, machine_id) DO NOTHING;

-- Precios promo_state: $39 Personal (2 Macs) / $59 Familiar (5 Macs)
ALTER TABLE promo_state ALTER COLUMN promo_price SET DEFAULT 39.00;
ALTER TABLE promo_state ALTER COLUMN regular_price SET DEFAULT 59.00;
UPDATE promo_state SET promo_price = 39.00, regular_price = 59.00 WHERE id = 1;

-- Referidos y planes en customers / orders
ALTER TABLE customers ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS referral_code TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'personal';

CREATE TABLE IF NOT EXISTS referrals (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_customer_id  UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  referred_order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  referral_code         TEXT NOT NULL,
  discount_applied_usd  NUMERIC(10,2) NOT NULL DEFAULT 4.00,
  commission_amount_usd NUMERIC(10,2) NOT NULL DEFAULT 10.00,
  status                TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'refunded_to_card', 'paid_out', 'cancelled')),
  stripe_refund_id      TEXT,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS referrals_referrer_idx ON referrals (referrer_customer_id);
CREATE INDEX IF NOT EXISTS referrals_order_idx ON referrals (referred_order_id);
CREATE INDEX IF NOT EXISTS referrals_code_idx ON referrals (referral_code);
