# Operations runbook

This is the playbook for running LastSeen's tracker fleet in production.

## Pairing a fresh scraper account

> Scrapers are real WhatsApp accounts. They MUST be aged numbers (active for at least 90 days) with normal organic activity. Freshly bought numbers get banned within hours.

1. Acquire a SIM (or eSIM) and activate the WhatsApp account on a phone for at least a week. Send/receive a few messages organically. Do NOT use the same proxy/IP your server runs on yet.
2. SSH into the production host (or run admin curl from your machine):
   ```bash
   curl -u $ADMIN_USER:$ADMIN_PASS -X POST https://api.lastseen.app/admin/scrapers \
     -H 'content-type: application/json' \
     -d '{"label":"primary-tr-1","capacity":50}'
   ```
3. Wait ~10 seconds for the worker to spin up the Baileys session, then:
   ```bash
   curl -u $ADMIN_USER:$ADMIN_PASS \
     "https://api.lastseen.app/admin/scrapers/<id>/qr?format=png" -o qr.png
   open qr.png
   ```
4. On the phone, open WhatsApp → Settings → Linked Devices → Link a Device → scan the QR.
5. Confirm `status` flipped to `WARMING`:
   ```bash
   curl -u $ADMIN_USER:$ADMIN_PASS https://api.lastseen.app/admin/scrapers | jq
   ```
6. **Wait 24 hours** before letting the system assign real users to this scraper. The `WARMING → HEALTHY` transition is automatic at the end of `warmupUntil`.

## Recovering a banned scraper

If `status === 'BANNED'`:

1. The scraper's `banReason` will hint at the cause (`loggedOut` is the most common — could be a manual logout from another device, or a soft ban).
2. Don't try to re-pair the same number immediately; the JID is likely flagged.
3. Reassign its tracked numbers to other healthy scrapers:
   ```sql
   UPDATE tracked_numbers
   SET "scraperAccountId" = NULL
   WHERE "scraperAccountId" = '<bannedId>' AND "archivedAt" IS NULL;
   ```
   Then bump those numbers to re-enqueue tracking jobs:
   ```bash
   redis-cli LPUSH bull:tracking:wait '...'  # easier to redeploy worker
   ```
4. Mark the scraper retired:
   ```bash
   curl -u $ADMIN_USER:$ADMIN_PASS -X DELETE \
     https://api.lastseen.app/admin/scrapers/<id>
   ```
5. Provision a replacement and pair as above.

## Rotating proxies

Each scraper can have a `proxyUrl` (residential SOCKS5/HTTPS). To rotate:

1. Update the row:
   ```sql
   UPDATE scraper_accounts SET "proxyUrl" = 'socks5://user:pass@host:port' WHERE id = '...';
   ```
2. Restart the worker pod for that scraper. (Roll the worker — sessions auto-reconnect on the new proxy.)

We don't currently route Baileys traffic through the configured `proxyUrl` — wire it via a global agent in `baileysSession.ts` if you need it.

## Replaying events

If presence ingestion was paused or wedged for a while (e.g. Redis outage), no replay is needed: Baileys re-subscribes automatically on reconnect, and rollups read whatever events made it into the DB. Today's rollup is rebuilt every hour by the cron job.

To force a backfill of the daily rollup:
```bash
node -e "
import('./dist/modules/reports/rollups.js').then(async m => {
  await m.rebuildDailyRollup('<trackedNumberId>', '2026-04-29');
});
"
```

## Backups

- Postgres: nightly `pg_dump` to S3 via `infra/backup.sh` (cron). Retention: 30 days hot + 1 year cold.
- Baileys auth state lives in S3 (`baileys-auth` bucket). Versioned.
- Redis is treated as ephemeral — any in-flight job loss is acceptable; the next cron round picks up.

## Capacity

- One Baileys session ~ 50 tracked numbers comfortably (configurable per scraper).
- Above ~75 you'll see WhatsApp throttling presence updates.
- Plan for 1 scraper per 30 paying users.

## Health checks

- `GET /health` on the API returns `{ ok: true }` if the process is up. Doesn't verify DB.
- Each scraper updates `lastHeartbeat` whenever a `paired` event fires (i.e. on (re)connect). If `now - lastHeartbeat > 1h` for a HEALTHY scraper, the connection is wedged — restart the worker.

## Common alerts

- "presence ingest dropped > 50% in 5m": likely WhatsApp connection dropped on multiple scrapers. Check Sentry for Boom timeouts.
- "scraper status=BANNED": page on call. Replace within 4h to keep customer-visible coverage.
- "apple notification processing failed": check the `apple_notifications` table for the offending payload.
