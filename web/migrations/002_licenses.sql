-- Licencias: trial 5 días (1 Mac) o Pro de por vida (1 Mac)
CREATE TABLE IF NOT EXISTS licenses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  order_id      UUID REFERENCES orders(id) ON DELETE SET NULL,
  license_key   TEXT NOT NULL UNIQUE,
  plan          TEXT NOT NULL CHECK (plan IN ('trial', 'pro')),
  seats         INT NOT NULL DEFAULT 1,
  expires_at    TIMESTAMPTZ,
  machine_id    TEXT,
  activated_at  TIMESTAMPTZ,
  revoked       BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS licenses_customer_idx ON licenses (customer_id);
CREATE INDEX IF NOT EXISTS licenses_key_idx ON licenses (license_key);

-- Un trial activo por correo (no acumular trials)
CREATE UNIQUE INDEX IF NOT EXISTS licenses_one_trial_per_customer
  ON licenses (customer_id)
  WHERE plan = 'trial';
