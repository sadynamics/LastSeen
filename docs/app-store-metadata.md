# App Store metadata

## Bundle

- Bundle ID: `collabrainstech.LastSeen`
- App name: `LastSeen`
- Subtitle (30 chars): `Family WhatsApp Activity`
- Primary category: `Productivity`
- Secondary category: `Lifestyle`
- Age rating: 4+

## Subscriptions (App Store Connect → In-App Purchases)

| Reference name | Product ID | Type | Duration | Price (USD) | Free trial |
|---|---|---|---|---|---|
| Weekly Pro | `collabrainstech.LastSeen.weekly` | Auto-renewable | 1 week | $5.99 | 3 days |
| Yearly Pro | `collabrainstech.LastSeen.yearly` | Auto-renewable | 1 year | $59.99 | 3 days |

Both products belong to the subscription group **`collabrainstech.LastSeen.group`**. The app uses raw StoreKit 2; no RevenueCat.

## Server-to-Server notifications

- Notification URL (production): `https://api.lastseen.app/v1/billing/apple-notifications`
- Notification URL (sandbox): `https://api.lastseen.app/v1/billing/apple-notifications`
- Version: 2

## Capabilities required

- Sign in with Apple
- Push Notifications
- In-App Purchase

## App Privacy questionnaire answers

| Data type | Linked to user | Used for | Disclosed |
|---|---|---|---|
| Identifiers → Apple ID `sub` | Yes | App functionality | Yes |
| Identifiers → User-provided phone numbers | Yes | App functionality | Yes |
| Identifiers → APNs device token | Yes | App functionality | Yes |
| User content → Display names | Yes | App functionality | Yes |
| Diagnostics → Crash data | No | App functionality | Yes |
| Usage data → Product interaction | No | Analytics | No (we don't collect this) |

We do NOT collect: location, contacts, browsing history, search history, advertising data, financial info beyond Apple-handled purchases.

## Description (4,000 char limit)

```
LastSeen is the easiest way to understand your family's WhatsApp screen-time and have informed conversations about phone use.

Add a phone number you own or a family member who's given you consent, and LastSeen quietly tracks how much time they spend online — broken down by day, by hour, and by session.

Made for parents, partners with consent, and anyone who wants to monitor their own activity.

KEY FEATURES

• Live status — see right now whether a tracked number is online
• Daily timeline — every session of the day, with start, end, and duration
• Weekly report — clear bar chart of activity, peak hours, daily average
• Smart notifications — daily summary by default, optional online and offline alerts
• Quiet hours — silence pings at night
• Privacy-first — Sign in with Apple, no contacts uploaded, no ads, no third-party trackers

USED RESPONSIBLY
LastSeen is for monitoring accounts you own, your minor children, or family members who've given you informed consent. The onboarding flow asks you to confirm this. Tracking someone without their consent may be illegal where you live.

SUBSCRIPTION
LastSeen is free to try with one tracked number. Pro unlocks unlimited numbers, real-time alerts, and weekly reports.

• Weekly Pro: $5.99 / week — 3 day free trial
• Monthly Pro: $19.99 / month — 3 day free trial

Subscriptions auto-renew until cancelled. Cancel anytime: Settings → Apple ID → Subscriptions.

Privacy policy: https://lastseen.app/privacy
Terms of service: https://lastseen.app/terms
Support: support@lastseen.app
```

## Keywords (100 chars)

```
last seen,whatsapp,online tracker,family,monitor,activity,parental,screen time,whats,wa,tracker
```

## Screenshots needed (6.5" iPhone)

1. **Hero** — Tracked numbers list with two cards showing "Online for 4m" and "Last seen 12m ago" pills. Caption: "See activity at a glance."
2. **Detail timeline** — Detail view with today's bar timeline. Caption: "Every session, every day."
3. **Weekly chart** — 7-day bar chart. Caption: "Patterns over the week."
4. **Notifications** — Toggles. Caption: "Pinged only when it matters."
5. **Onboarding consent screen** — Caption: "Used responsibly, with consent."
6. **Paywall** — Caption: "Try free for 3 days."

All screenshots should reinforce the family/personal-monitoring framing per [app-review.md](app-review.md).
