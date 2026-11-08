ALTER TABLE download_tokens
  ALTER COLUMN order_id DROP NOT NULL;

ALTER TABLE download_tokens
  ADD COLUMN IF NOT EXISTS license_id UUID REFERENCES licenses(id) ON DELETE CASCADE;
