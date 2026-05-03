# Launch checklist

Run through this before submitting v1.0 to TestFlight, then again before App Store release.

## Backend

- [ ] `JWT_SECRET` set to a random ≥64-char string (`openssl rand -base64 64`).
- [ ] `ADMIN_BASIC_PASSWORD` rotated and stored in 1Password.
- [ ] Apple In-App Purchase `.p8` key generated, base64-encoded, in `APPLE_INAPP_PRIVATE_KEY_BASE64`.
- [ ] APNs `.p8` key generated, base64-encoded, in `APNS_PRIVATE_KEY_BASE64`.
- [ ] `APNS_ENVIRONMENT=production` and `APPLE_INAPP_ENVIRONMENT=Production` set for prod.
- [ ] Postgres + TimescaleDB running on production host.
- [ ] `prisma migrate deploy` applied.
- [ ] `prisma/sql/timescale.sql` applied (one-time, hypertable creation).
- [ ] At least 1 scraper account paired and in `HEALTHY` status.
- [ ] Sentry DSN configured.
- [ ] Daily backup cron (`infra/backup.sh`) wired up.
- [ ] Caddy fronting the API with auto-TLS for `api.lastseen.app`.
- [ ] Apple S2S notification URL configured in App Store Connect.

## iOS

- [ ] `API_BASE_URL` env var (Xcode scheme) points to production for Release builds.
- [ ] StoreKit configuration disabled for Release (no `LastSeenStoreKit.storekit` selected).
- [ ] App Icon present in `Assets.xcassets`.
- [ ] Privacy policy URL `https://lastseen.app/privacy` live.
- [ ] Terms URL `https://lastseen.app/terms` live.
- [ ] Sign in with Apple capability enabled in target's Signing & Capabilities.
- [ ] Push Notifications capability enabled.
- [ ] `aps-environment` entitlement set to `production` for Release.

## App Store Connect

- [ ] Subscription products `lastseen.pro.weekly` and `lastseen.pro.monthly` created and submitted with the app build.
- [ ] App Privacy questionnaire filled (see [app-store-metadata.md](app-store-metadata.md)).
- [ ] App Review notes include test credentials.
- [ ] Screenshots reinforce family / consent framing (see [app-review.md](app-review.md)).
- [ ] Promotional text avoids "spy / track anyone" language.
- [ ] Build uploaded via Xcode Organizer / `xcrun altool`.

## Smoke tests on TestFlight

1. Sign in with Apple (fresh account) → onboarding shows up.
2. Tick consent → continue → notifications prompt.
3. Add a phone number you own (one that's actively using WhatsApp).
4. Within 30 seconds the live status pill flips to "Online for ..." when you open WhatsApp on that phone.
5. Lock that phone, wait 1 minute, refresh → "Last seen 1m ago".
6. Open the detail view → today's timeline shows the session.
7. Try to add a 2nd number → paywall.
8. Subscribe with a sandbox tester → 2nd number adds OK.
9. Restart the app → still subscribed, list still shows correctly.
10. Settings → Delete account → sign in again → all data gone.

## Day-1 monitoring

- Watch Sentry for new error groups in the first 4 hours.
- Watch `scraper_accounts.status` — if anything flips to `BANNED`, follow [runbook.md](runbook.md).
- Watch APNs feedback for invalid token rates (>2% means a bug in `/v1/devices`).
