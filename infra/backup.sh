#!/usr/bin/env bash
# Daily Postgres backup script.
# Run from cron at e.g. `5 3 * * * /opt/lastseen/infra/backup.sh`

set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET is required}"
: "${BACKUP_S3_PREFIX:=postgres}"

ts="$(date -u +%Y%m%d_%H%M%S)"
tmp="/tmp/lastseen-${ts}.sql.gz"

echo "[backup] dumping..."
pg_dump --no-owner --no-acl --format=plain "$DATABASE_URL" | gzip -9 > "$tmp"

echo "[backup] size: $(du -h "$tmp" | cut -f1)"
echo "[backup] uploading to s3://${BACKUP_S3_BUCKET}/${BACKUP_S3_PREFIX}/${ts}.sql.gz"
aws s3 cp --no-progress "$tmp" "s3://${BACKUP_S3_BUCKET}/${BACKUP_S3_PREFIX}/${ts}.sql.gz"

rm -f "$tmp"

# Retention: keep last 30 daily, then weekly for a year, then monthly forever.
# Implemented by S3 lifecycle rules; this script just uploads.

echo "[backup] done"
