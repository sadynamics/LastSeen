# LastSeen

A WhatsApp activity tracker — iOS app + Node.js backend.

## Repo layout

- `ios/` — SwiftUI client (Xcode project, iOS 26+, Swift 6, multi-platform).
- `backend/` — TypeScript service (Fastify API + BullMQ tracker workers + Baileys WhatsApp sessions).
- `infra/` — Docker Compose for local Postgres + TimescaleDB + Redis, deploy assets.
- `docs/` — Privacy policy, terms, App Review framing notes, ops runbook.

## Quick start

### 1. Local infrastructure

```bash
cd infra
docker compose up -d
```

This brings up Postgres (with TimescaleDB) on `localhost:5432`, Redis on `localhost:6379`, and a MinIO bucket for Baileys auth-state on `localhost:9000`.

### 2. Backend

```bash
cd backend
cp .env.example .env
pnpm install
pnpm prisma migrate deploy
pnpm dev          # API on :3000
pnpm dev:worker   # tracker worker
```

### 3. iOS app

Open `ios/LastSeen.xcodeproj` in Xcode 26+. Set `API_BASE_URL` in the `LastSeen` scheme's environment variables (default: `http://localhost:3000`). Build & run on a device or simulator.

### 4. Deploy to production

See [docs/deploy-railway.md](docs/deploy-railway.md) for the full Railway deployment walkthrough, or run `./infra/railway-deploy.sh` to bootstrap the project.

## How presence tracking works

The backend keeps a small pool of real WhatsApp accounts paired through Baileys. For every tracked phone number we call `presenceSubscribe(jid)` on the assigned scraper account; WhatsApp then streams `available`/`unavailable`/`composing`/`recording` updates which we timestamp into a TimescaleDB hypertable. Hourly + nightly rollups produce the daily/weekly reports the iOS app shows.

See [docs/runbook.md](docs/runbook.md) for warm-up, ban recovery, and proxy rotation.

## App Review framing

This app is positioned as a **family/personal usage monitor**, not a third-party tracker. All marketing copy, screenshots, and onboarding must reinforce that framing. See [docs/app-review.md](docs/app-review.md).

## License

Proprietary. All rights reserved.
