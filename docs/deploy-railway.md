# Deploying LastSeen to Railway

End-to-end production deploy. Plan on ~30 minutes the first time.

You're shipping **two long-running services** from one repo:
- **`api`** — Fastify HTTP server (public, behind a Railway domain)
- **`worker`** — BullMQ worker that runs Baileys sessions and pushes APNs notifications (private)

Plus three managed dependencies:
- **Postgres** (Railway plugin; optionally swap for TimescaleDB)
- **Redis** (Railway plugin)
- **S3-compatible storage** for Baileys auth state (Cloudflare R2 — outside Railway, free tier is plenty)

---

## 0) Prereqs

- Railway account at <https://railway.com>
- GitHub: this repo pushed to a remote you control
- Apple Developer + App Store Connect access (for APNs key, StoreKit key, bundle ID)
- A domain you can point at Railway (e.g. `api.lastseen.app`) — optional for first deploy
- CLI:

  ```bash
  brew install railway
  # or
  npm i -g @railway/cli

  railway login
  ```

---

## 1) Bootstrap the project

From the repo root:

```bash
./infra/railway-deploy.sh
```

What it does:
1. Verifies the CLI is installed and you're logged in
2. Runs `railway init` to create a new project (or links to an existing one)
3. Adds the Postgres and Redis plugins
4. Generates `.env.railway.generated` with strong random secrets you can copy/paste

The script intentionally stops there — Railway's CLI can't fully script "deploy this monorepo as two distinct services from the same GitHub source", so the next 3 minutes happen in the dashboard.

---

## 2) Create the API service

In the Railway dashboard for your project:

1. **New → GitHub Repo** → pick the LastSeen repo (authorize Railway if needed)
2. Open the new service → **Settings**:
   - **Service Name:** `api`
   - **Root Directory:** `backend`
   - **Builder:** auto-detected as Dockerfile via `backend/railway.json`
   - **Watch Paths:** auto (already pinned in `railway.json` to `backend/**`)
3. **Networking → Public Networking → Generate Domain** (gives you `api-production-XXXX.up.railway.app`)
4. **Variables → Raw Editor** → paste the contents of `.env.railway.generated`, then fill in:
   - `APPLE_TEAM_ID`
   - `APPLE_INAPP_KEY_ID`, `APPLE_INAPP_ISSUER_ID`, `APPLE_INAPP_PRIVATE_KEY_BASE64`
   - `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY_BASE64`
   - `S3_*` (R2 — see step 4)
   - `SENTRY_DSN` (optional, recommended)

   The `${{Postgres.DATABASE_URL}}` and `${{Redis.REDIS_URL}}` references are Railway template strings — they auto-resolve to the plugins you added.

5. Save. Railway will trigger the first deploy.

`backend/scripts/start-api.js` runs `prisma migrate deploy` and the Timescale init on boot, so the DB is ready before the API starts listening.

---

## 3) Create the Worker service

1. **New → GitHub Repo** → same repo as API
2. **Settings:**
   - **Service Name:** `worker`
   - **Root Directory:** `backend`
   - **Networking:** leave private (no public domain — workers don't need one)
3. **Variables:**
   - Paste the same `.env.railway.generated` contents
   - **Add one extra variable:** `RAILWAY_CONFIG_FILE=railway.worker.json`
     This tells Railway to use [`backend/railway.worker.json`](../backend/railway.worker.json), which sets the start command to `node scripts/start-worker.js`.
4. Save → first deploy starts.

---

## 4) Set up R2 (Cloudflare object storage) for Baileys auth state

Why R2: Baileys serializes its session keys (~100 KB per scraper) and we don't want them on a service container's ephemeral disk — restarts would re-trigger QR pairing every time. R2 has zero egress fees and a free tier that fits this comfortably.

1. <https://dash.cloudflare.com> → **R2** → **Create bucket** → name it `lastseen-baileys-prod`
2. **Manage R2 API Tokens → Create token**
   - Permissions: **Object Read & Write**
   - Specify bucket: `lastseen-baileys-prod`
   - Copy the **Access Key ID**, **Secret Access Key**, and **endpoint URL** (looks like `https://<accountid>.r2.cloudflarestorage.com`)
3. Back in Railway, on **both** API and Worker services, set:

   ```
   S3_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
   S3_REGION=auto
   S3_ACCESS_KEY_ID=...
   S3_SECRET_ACCESS_KEY=...
   S3_BUCKET_BAILEYS=lastseen-baileys-prod
   S3_FORCE_PATH_STYLE=true
   ```

---

## 5) (Optional) Swap stock Postgres for TimescaleDB

The app works fine on plain Postgres — `init-timescale.js` skips silently when the extension isn't available. But if you want hypertable retention + compression on `presence_events` (recommended for production):

1. Railway dashboard → **New → Docker Image**
2. Image: `timescale/timescaledb:latest-pg16`
3. **Variables:**
   - `POSTGRES_USER=lastseen`
   - `POSTGRES_PASSWORD=<random>` (use `openssl rand -hex 24`)
   - `POSTGRES_DB=lastseen`
4. **Volumes:** mount `/var/lib/postgresql/data` (Railway will provision a persistent volume)
5. **Networking → Private Networking** is already on by default; note the internal hostname (e.g. `timescale.railway.internal:5432`)
6. Construct the URL: `postgres://lastseen:<password>@timescale.railway.internal:5432/lastseen`
7. **API service → Variables:** replace `DATABASE_URL=${{Postgres.DATABASE_URL}}` with the new URL above
8. Same for the Worker service
9. Redeploy both. On boot, `init-timescale.js` will run `CREATE EXTENSION IF NOT EXISTS timescaledb`, convert `presence_events` to a hypertable, and apply retention/compression policies.
10. Once you've verified everything is on the new DB (run a couple of API calls, check `/health`, look at `presence_events` row counts), delete the stock Postgres plugin to stop being billed for it.

---

## 6) Pair the first scraper account

Workers can't subscribe to presence until at least one Baileys session is paired with a real WhatsApp account. This is a one-time, ~30-second flow:

```bash
# Replace API_URL with your Railway domain and ADMIN_BASIC_PASSWORD with the
# value from your env (look in the API service variables in Railway).
curl -u admin:<ADMIN_BASIC_PASSWORD> \
  -X POST https://<API_URL>/admin/scrapers/pair \
  -H 'Content-Type: application/json' \
  -d '{"label":"primary"}'
```

The response includes a QR code (data URL). Open it in a browser, scan it from a **dedicated WhatsApp account** (use a SIM you control — see [docs/runbook.md](runbook.md) for warming guidance), and the worker will mark the session active.

> Critical: do NOT pair your personal WhatsApp. Use a SIM dedicated to LastSeen so a future ban doesn't wipe out your real chats.

---

## 7) Custom domain (optional but recommended)

1. API service → **Networking → Custom Domain → Add `api.lastseen.app`**
2. Railway shows you a CNAME target (e.g. `XXXX.up.railway.app`)
3. In your DNS provider, create the CNAME record
4. Railway provisions a TLS cert automatically once DNS resolves
5. Update the iOS client's [`AppConfig.swift`](../ios/LastSeen/App/AppConfig.swift) `apiBaseURL` to your custom domain and rebuild

---

## 8) Apple S2S notifications endpoint

App Store Server Notifications V2 will POST subscription lifecycle events to your API. Configure in App Store Connect:

1. <https://appstoreconnect.apple.com> → My Apps → LastSeen → **App Information → App Store Server Notifications**
2. **Production Server URL:** `https://api.lastseen.app/v1/billing/apple/notifications`
3. **Sandbox Server URL:** same domain (the backend reads the environment claim from the signed payload)
4. **Version:** Version 2

The handler is in [`backend/src/api/routes/billing.ts`](../backend/src/api/routes/billing.ts) and uses Apple's official `app-store-server-library` to verify JWS signatures.

---

## 8b) Firebase Admin (Firestore customer mirror) — optional

The backend can mirror customer rows + purchases to Firestore so you have a CRM-style view of every signup, subscription, and refund alongside the data Firebase Analytics already collects. Skipping this is fine for a first deploy — leave the env vars blank and the sync gracefully no-ops.

1. <https://console.firebase.google.com> → your project → **Project Settings → Service accounts**
2. Click **Generate new private key** → confirm → a JSON file downloads
3. Open the JSON, copy these three fields into the Railway **api** service variables:

   | Railway env var | JSON field |
   | --- | --- |
   | `FIREBASE_PROJECT_ID` | `project_id` |
   | `FIREBASE_CLIENT_EMAIL` | `client_email` |
   | `FIREBASE_PRIVATE_KEY` | `private_key` (paste the full string with literal `\n` between lines — Railway preserves them, the backend converts them at boot) |

4. (Optional) In the Firebase console → **Build → Firestore Database** → **Create database** in **production mode** if you haven't already. Pick the region nearest your Railway region.
5. Redeploy the API service. Look for `firebase admin initialised` in the logs.
6. Verify by signing in once from the iOS app, then in Firebase Console → Firestore → `users/<userId>` should have a fresh document with `email`, `appleSub`, `lastSignInAt`, etc.

What gets written:
- `users/{userId}`: `appleSub`, `email`, `locale`, `createdAt`, `lastSignInAt`, `deletedAt`, `trackedCount`, `subscription` (snapshot of current subscription).
- `users/{userId}/purchases/{originalTransactionId}`: every transaction Apple sends, including renewals, cancellations, refunds. Updated by both the iOS-initiated `/v1/billing/verify` call and Apple's S2S notifications.

The sync is fire-and-forget: a Firebase outage or quota error never blocks an API response.

---

## 9) Verify the deploy

```bash
# Health check
curl https://<API_URL>/health
# → {"ok":true,"service":"lastseen-backend","ts":"..."}

# Check API logs in Railway dashboard:
#   - "[start-api] applying migrations..."
#   - "[init-timescale] done."  (or "skipping hypertable setup")
#   - "api started" (port 3000)

# Check Worker logs:
#   - "[start-worker] applying migrations..."
#   - "tracking worker ready" (from src/workers/trackingWorker.ts)
```

---

## 10) Ongoing operations

- **Pushing updates:** `git push origin main` → Railway auto-builds and rolling-deploys both services. Health checks gate the API rollout (60s timeout in `railway.json`).
- **Logs:** dashboard → service → **Deployments → <build> → Logs**, or `railway logs --service api`
- **Shell into a service:** `railway run --service api bash`
- **Run a one-off Prisma command:** `railway run --service api npx prisma studio`
- **Roll back:** dashboard → **Deployments** → click the previous green build → **Redeploy**
- **Scale:** Settings → **Resources** (vertical) and `numReplicas` in `railway.json` (horizontal — only safe for the API; the worker should stay at 1 unless you partition queues)

See [docs/runbook.md](runbook.md) for scraper warm-up, ban recovery, and incident response.

---

## Cost expectations

Hobby plan is enough to launch:
- **$5/mo Hobby** + **usage** (RAM/CPU/network) → typically ~$10–20/mo total for the first hundred users with one scraper
- Each new scraper = ~+$5/mo (one extra worker replica or, if you partition, one extra worker service)
- Postgres usage scales with `presence_events` cardinality; retention policy keeps it bounded at 90 days

If you need higher availability later, upgrade to **Pro** ($20/mo) for guaranteed regions, longer log retention, and priority support.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails with `prisma generate` not found | Dockerfile wasn't picked up | Verify Service → Settings → Root Directory = `backend` |
| `PrismaClientInitializationError: connection refused` | DATABASE_URL not set or Postgres plugin not attached | Variables tab — confirm `${{Postgres.DATABASE_URL}}` resolves |
| Worker logs show `BullMQ requires a redis-compatible store` | REDIS_URL missing | Same — confirm Redis plugin attached |
| `init-timescale` errors but API stays up | Extension unavailable on stock Postgres | Expected. Either swap to TimescaleDB image or ignore — the policies just don't apply |
| Pair endpoint returns 401 | ADMIN_BASIC_PASSWORD mismatch | Pull the value from Variables tab; that's the source of truth |
| iOS app can't reach API | Wrong base URL or HTTP not HTTPS | `AppConfig.swift` must use `https://`; ATS rejects `http` |
| Push notifications never arrive | APNS_PRIVATE_KEY_BASE64 has whitespace/newlines | Use `cat AuthKey_XXXX.p8 \| base64 \| tr -d '\n'` and paste the single-line result |

