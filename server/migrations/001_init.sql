-- MedStation initial schema.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Every imported dataset gets a row. Records reference it so the API can
-- return source / version / fetch date with every answer.
CREATE TABLE data_sources (
  id          SERIAL PRIMARY KEY,
  kind        TEXT NOT NULL,          -- drugs | interactions | dose_limits | documents | announcements
  source      TEXT NOT NULL,
  version     TEXT NOT NULL,
  url         TEXT,
  fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_sample   BOOLEAN NOT NULL DEFAULT false,
  row_count   INT,
  skipped     INT,
  active      BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE drugs (
  id               TEXT PRIMARY KEY,
  barcode          TEXT UNIQUE,
  name             TEXT NOT NULL,
  name_fold        TEXT NOT NULL,
  firm             TEXT,
  form             TEXT,
  form_group       TEXT NOT NULL DEFAULT 'diger',
  strength         TEXT,
  pack             TEXT,
  atc              TEXT,
  rx_type          TEXT NOT NULL DEFAULT 'bilinmiyor',
  sgk_status       TEXT,
  psf              NUMERIC(12,2),
  equivalence_code TEXT,
  storage          TEXT,
  kub_url          TEXT,
  kt_url           TEXT,
  recalled         BOOLEAN NOT NULL DEFAULT false,
  source_id        INT NOT NULL REFERENCES data_sources(id)
);
CREATE INDEX drugs_name_trgm ON drugs USING gin (name_fold gin_trgm_ops);
CREATE INDEX drugs_atc ON drugs (atc);

CREATE TABLE drug_ingredients (
  drug_id       TEXT NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
  position      INT NOT NULL,
  name          TEXT NOT NULL,
  base_key      TEXT NOT NULL,          -- medstation_core baseIngredient()
  fold          TEXT NOT NULL,          -- medstation_core searchFold(base_key)
  amount        DOUBLE PRECISION,
  unit          TEXT,
  per_volume_ml DOUBLE PRECISION,
  PRIMARY KEY (drug_id, position)
);
CREATE INDEX drug_ingredients_base ON drug_ingredients (base_key);
CREATE INDEX drug_ingredients_fold ON drug_ingredients USING gin (fold gin_trgm_ops);

-- Clinical reference data. Rows without a source are rejected.
CREATE TABLE interactions (
  id          SERIAL PRIMARY KEY,
  a           TEXT NOT NULL,
  b           TEXT NOT NULL,
  severity    TEXT NOT NULL CHECK (severity IN ('kritik','onemli','bilgi')),
  summary     TEXT NOT NULL,
  management  TEXT,
  source      JSONB NOT NULL,
  source_id   INT NOT NULL REFERENCES data_sources(id)
);
CREATE INDEX interactions_pair ON interactions (a, b);

CREATE TABLE interaction_coverage (
  ingredient  TEXT NOT NULL,
  source_id   INT NOT NULL REFERENCES data_sources(id),
  PRIMARY KEY (ingredient, source_id)
);

CREATE TABLE dose_limits (
  id               SERIAL PRIMARY KEY,
  ingredient       TEXT NOT NULL,
  population       TEXT NOT NULL CHECK (population IN ('yetiskin','pediatrik')),
  unit             TEXT NOT NULL,
  max_daily        DOUBLE PRECISION,
  max_daily_per_kg DOUBLE PRECISION,
  source           JSONB NOT NULL,
  source_id        INT NOT NULL REFERENCES data_sources(id),
  CHECK (max_daily IS NOT NULL OR max_daily_per_kg IS NOT NULL)
);

CREATE TABLE announcements (
  id           TEXT PRIMARY KEY,
  type         TEXT NOT NULL,
  title        TEXT NOT NULL,
  summary      TEXT,
  url          TEXT UNIQUE,
  published_at TIMESTAMPTZ NOT NULL,
  source_id    INT NOT NULL REFERENCES data_sources(id)
);
CREATE INDEX announcements_pub ON announcements (published_at DESC);

CREATE TABLE recalls (
  barcode         TEXT NOT NULL,
  lot             TEXT,
  announcement_id TEXT REFERENCES announcements(id),
  PRIMARY KEY (barcode, announcement_id)
);

-- KÜB / KT passages for retrieval-augmented answers.
CREATE TABLE doc_chunks (
  id            TEXT PRIMARY KEY,
  drug_id       TEXT REFERENCES drugs(id) ON DELETE SET NULL,
  drug_name     TEXT NOT NULL,
  document      TEXT NOT NULL CHECK (document IN ('KÜB','KT')),
  section       TEXT,
  url           TEXT,
  document_date DATE,
  content       TEXT NOT NULL,
  embedding     vector(1536) NOT NULL,
  source_id     INT NOT NULL REFERENCES data_sources(id)
);
CREATE INDEX doc_chunks_embedding ON doc_chunks USING hnsw (embedding vector_cosine_ops);

CREATE TABLE pharmacies (
  id    TEXT PRIMARY KEY,
  name  TEXT NOT NULL,
  gln   TEXT
);

CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  pharmacy_id   TEXT NOT NULL REFERENCES pharmacies(id),
  email         TEXT NOT NULL UNIQUE,
  full_name     TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('eczaci','teknisyen','admin')),
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked     BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE audit_log (
  id         BIGSERIAL PRIMARY KEY,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    TEXT REFERENCES users(id),
  action     TEXT NOT NULL,
  entity     TEXT,
  entity_id  TEXT,
  data       JSONB
);

-- Prescription checks hold no patient identity (KVKK): only drug lines,
-- anonymous age/weight and the findings.
CREATE TABLE prescription_checks (
  id          TEXT PRIMARY KEY,
  pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id),
  user_id     TEXT NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  request     JSONB NOT NULL,
  findings    JSONB NOT NULL
);

CREATE TABLE finding_decisions (
  check_id   TEXT NOT NULL REFERENCES prescription_checks(id) ON DELETE CASCADE,
  finding_id TEXT NOT NULL,
  decision   TEXT NOT NULL CHECK (decision IN ('onaylandi','reddedildi','not')),
  note       TEXT,
  user_id    TEXT NOT NULL REFERENCES users(id),
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (check_id, finding_id)
);

CREATE TABLE stock_items (
  id             TEXT PRIMARY KEY,
  pharmacy_id    TEXT NOT NULL REFERENCES pharmacies(id),
  drug_id        TEXT NOT NULL REFERENCES drugs(id),
  critical_level INT NOT NULL DEFAULT 0,
  UNIQUE (pharmacy_id, drug_id)
);

CREATE TABLE stock_batches (
  id        TEXT PRIMARY KEY,
  item_id   TEXT NOT NULL REFERENCES stock_items(id) ON DELETE CASCADE,
  lot       TEXT,
  serial    TEXT,
  expiry    DATE,
  quantity  INT NOT NULL CHECK (quantity >= 0)
);

CREATE TABLE favorites (
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  drug_id    TEXT NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, drug_id)
);

