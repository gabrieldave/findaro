-- 006_attribution.sql
-- T-04: Una prueba por equipo (hash con sal)
-- T-06: Atribución first-touch UTM y registro de eventos del embudo

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

-- 3. Tabla de eventos del embudo con deduplicación estricta
CREATE TABLE IF NOT EXISTS events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  subject_type  TEXT,
  subject_id    TEXT,
  dedup_key     TEXT UNIQUE,
  props         JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS events_name_idx ON events (name);
CREATE INDEX IF NOT EXISTS events_occurred_idx ON events (occurred_at);
CREATE INDEX IF NOT EXISTS events_dedup_idx ON events (dedup_key);
