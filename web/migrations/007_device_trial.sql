-- 007_device_trial.sql
-- Prueba de 5 días anclada en el servidor por equipo (hash con sal del hardware).
-- Antes el inicio de la prueba vivía solo en el Llavero del Mac: borrarlo reiniciaba los 5 días.
ALTER TABLE trial_devices ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Rellenar filas existentes (pruebas por correo ya activadas) con su caducidad real.
UPDATE trial_devices d
SET expires_at = COALESCE(l.expires_at, d.first_seen_at + INTERVAL '5 days')
FROM licenses l
WHERE d.license_id = l.id AND d.expires_at IS NULL;

UPDATE trial_devices
SET expires_at = first_seen_at + INTERVAL '5 days'
WHERE expires_at IS NULL;
