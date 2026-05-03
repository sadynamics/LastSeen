# LastSeen Backend

TypeScript + Fastify API with Baileys-powered WhatsApp presence tracker workers.

## Run locally

```bash
# 1. Bring up infra (Postgres + Redis + MinIO)
cd ../infra && docker compose up -d

# 2. Install + migrate
cd ../backend
cp .env.example .env
pnpm install
pnpm prisma migrate dev --name init

# 3. Apply Timescale hypertable (one-time)
psql "$DATABASE_URL" -f prisma/sql/timescale.sql

# 4. Start API + worker in separate shells
pnpm dev          # API on :3000
pnpm dev:worker   # tracker workers
```

## Pairing your first scraper account

```bash
# Create a scraper row + enqueue a pair job
curl -u admin:change_me -X POST http://localhost:3000/admin/scrapers \
  -H 'content-type: application/json' \
  -d '{"label":"primary"}'

# Wait ~5 seconds for Baileys to spin up, then fetch the QR PNG
curl -u admin:change_me http://localhost:3000/admin/scrapers/<id>/qr -o qr.png
open qr.png
```

Scan the QR with WhatsApp on your phone (Settings → Linked Devices → Link a Device). Status will flip to `WARMING`. Wait 24h before assigning real users to it.

## Architecture

- `src/api/` — Fastify HTTP server
- `src/workers/` — BullMQ workers (tracking, notify, rollup)
- `src/modules/auth/` — Sign in with Apple
- `src/modules/tracking/` — Baileys session + scraper pool + presence ingest
- `src/modules/reports/` — daily/weekly rollups + queries
- `src/modules/billing/` — StoreKit 2 receipt verification + Apple S2S notifications
- `src/modules/push/` — APNs sender
- `src/config/` — env, prisma, redis, s3, logger
- `prisma/` — schema + migrations + Timescale SQL

## Production checklist

- Set `JWT_SECRET` to a random 64+ char string
- Generate Apple in-app `.p8` and APNs `.p8` keys, base64-encode and put in env
- Set `APNS_ENVIRONMENT=production`, `APPLE_INAPP_ENVIRONMENT=Production`
- Enable Sentry by setting `SENTRY_DSN`
- Run `pnpm prisma migrate deploy` then apply `prisma/sql/timescale.sql` once
- Run API and worker as separate services (separate Docker containers)
