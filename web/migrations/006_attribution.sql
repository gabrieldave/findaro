-- 006_attribution.sql
-- T-04: Una prueba por equipo (hash con sal)
-- T-06: Atribución first-touch UTM y registro de eventos del embudo (ADR-05)
-- T-01: Endurecimiento idempotente de pago y tabla stripe_events (ADR-04)

-- 1. Dispositivos que ya activaron una prueba (hash con sal del identificador de hardware)
CREATE TABLE IF NOT EXISTS trial_devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hardware_hash TEXT NOT NULL UNIQUE,
  license_id    UUID REFERENCES licenses(id) ON DELETE SET NULL,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS trial_devices_hash_idx ON trial_devices (hardware_hash);

-- 2. Atribución first-touch en customers
ALTER TABLE customers ADD COLUMN IF NOT EXISTS utm_source TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS utm_medium TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS utm_campaign TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS utm_content TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ DEFAULT now();

-- 3. Tabla de eventos del embudo (ADR-05) con unicidad (name, subject_type, subject_id, occurrence_key)
CREATE TABLE IF NOT EXISTS events (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  subject_type   TEXT NOT NULL,
  subject_id     TEXT NOT NULL,
  occurrence_key TEXT NOT NULL DEFAULT 'once',
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  props          JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT events_unique_occurrence UNIQUE (name, subject_type, subject_id, occurrence_key)
);

CREATE INDEX IF NOT EXISTS events_name_idx ON events (name);
CREATE INDEX IF NOT EXISTS events_occurred_idx ON events (occurred_at);
CREATE INDEX IF NOT EXISTS events_subject_idx ON events (subject_type, subject_id);

-- 4. Endurecimiento de pago (ADR-04)
CREATE TABLE IF NOT EXISTS stripe_events (
  event_id    TEXT PRIMARY KEY,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS email_claimed_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS email_sent_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS trial_license_id UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS stripe_payment_intent TEXT;
