-- Composition as published, SKRS market status, TİTCK license status.
ALTER TABLE drugs ADD COLUMN composition_text TEXT;
ALTER TABLE drugs ADD COLUMN market_status TEXT NOT NULL DEFAULT 'bilinmiyor';
ALTER TABLE drugs ADD COLUMN license_status INT NOT NULL DEFAULT -1;
ALTER TABLE drugs ADD COLUMN license_no TEXT;

-- Every stock change, per tenant and user (who received/dispensed what).
CREATE TABLE stock_movements (
  id          TEXT PRIMARY KEY,
  pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id),
  item_id     TEXT REFERENCES stock_items(id) ON DELETE SET NULL,
  drug_id     TEXT NOT NULL REFERENCES drugs(id),
  user_id     TEXT NOT NULL REFERENCES users(id),
  direction   TEXT NOT NULL CHECK (direction IN ('giris','cikis','duzeltme')),
  quantity    INT NOT NULL,
  lot         TEXT,
  serial      TEXT,
  expiry      DATE,
  note        TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX stock_movements_ph ON stock_movements (pharmacy_id, at DESC);

-- Supportive (commercial) products a pharmacy chooses to suggest. Always
-- shown separately from clinical findings; triggered by ATC prefix or
-- ingredient of a prescribed drug.
CREATE TABLE commercial_products (
  id            TEXT PRIMARY KEY,
  pharmacy_id   TEXT NOT NULL REFERENCES pharmacies(id),
  name          TEXT NOT NULL,
  note          TEXT,
  trigger_type  TEXT NOT NULL CHECK (trigger_type IN ('atc','ingredient')),
  trigger_value TEXT NOT NULL,
  active        BOOLEAN NOT NULL DEFAULT true,
  created_by    TEXT NOT NULL REFERENCES users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX commercial_products_ph ON commercial_products (pharmacy_id) WHERE active;
