-- Convert presence_events into a TimescaleDB hypertable.
-- Run AFTER `prisma migrate deploy` creates the table.

SELECT create_hypertable(
  'presence_events',
  'ts',
  chunk_time_interval => INTERVAL '7 days',
  if_not_exists => TRUE,
  migrate_data => TRUE
);

-- Drop chunks older than 90 days (free tier retention).
SELECT add_retention_policy(
  'presence_events',
  INTERVAL '90 days',
  if_not_exists => TRUE
);

-- Compression for chunks older than 7 days.
ALTER TABLE presence_events SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = '"trackedNumberId"',
  timescaledb.compress_orderby = 'ts DESC'
);

SELECT add_compression_policy(
  'presence_events',
  INTERVAL '7 days',
  if_not_exists => TRUE
);
