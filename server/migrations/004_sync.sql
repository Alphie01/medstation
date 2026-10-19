-- Structured metadata per imported dataset (e.g. which TİTCK files were used),
-- so the updater can tell whether a newer publication exists.
ALTER TABLE data_sources ADD COLUMN meta JSONB;

-- One row per automatic update run.
CREATE TABLE sync_runs (
  id          BIGSERIAL PRIMARY KEY,
  started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  status      TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running','ok','unchanged','error')),
  message     TEXT
);
