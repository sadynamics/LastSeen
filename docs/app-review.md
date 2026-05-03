# App Review framing

Apps in the WhatsApp activity tracking category survive App Review by being positioned as **personal / family monitoring tools with consent**, not as third-party tracking utilities. WaRadar, WeLastSeen, Zetlog, etc. all use this framing. We follow the same playbook.

## Marketing positioning

- **App name**: LastSeen
- **Subtitle**: "Family WhatsApp activity tracker"
- **Promotional text**: "Understand your family's WhatsApp screen time and have informed conversations about phone use."
- **Description first paragraph**: Open with parental / self-monitoring framing, never mention "spy", "track anyone", "ex-partner", or similar.

## Do / Don't copy guide

| Do | Don't |
|----|-------|
| "Monitor your child's online time" | "Spy on anyone" |
| "Track your own number's activity" | "Track your boyfriend / girlfriend / ex" |
| "Family activity reports" | "Catch them online" |
| "Used with the consent of the person being monitored" | (no mention of consent) |
| "Personal usage analytics" | "Real-time stalking" |

## In-app guardrails

These are implemented; do not remove without re-reading App Review guidelines:

1. **Hard-blocking consent gate** during onboarding: the user must tick "I confirm I will only track accounts I own or have permission to monitor." See [ios/LastSeen/Features/Onboarding/OnboardingFlow.swift](../ios/LastSeen/Features/Onboarding/OnboardingFlow.swift).
2. **Default-off real-time alerts**: the new tracked number's `NotificationPref.offlineEnabled` defaults to `false`, only `dailySummaryEnabled` and `onlineEnabled` are on. Reduces "creepy" framing of pings every time someone goes offline.
3. **Account deletion**: `DELETE /v1/me` end-to-end wipes user data. Required by App Review § 5.1.1(v).
4. **Privacy disclosures** in the App Privacy questionnaire:
   - Phone number → linked to user → used for app functionality only, not shared.
   - Crash data (Sentry) → not linked to user.
   - No location, contacts, or analytics SDKs.

## App Review notes (Connect → Build → "Notes")

> LastSeen is a family activity monitor for WhatsApp. To test, sign in with Apple, agree to the consent screen, and add a phone number you own. Use this test account:
>
> - Phone: +90 555 ... ...
> - Subscription: use Sandbox tester `qa@lastseen.app`
> - The tracked WhatsApp account is operated by us for testing purposes.

## Anticipated rejection patterns

1. **Guideline 5.1.2 (Data & Privacy → Data Use and Sharing)** — "Apps that collect personal information must allow users to revoke consent." Solved via account deletion.
2. **Guideline 4.0 (Design → Spam)** — "Apps that fail to enforce reasonable limits on … user interaction." Solved by onboarding consent + default-off intrusive notifications.
3. **Guideline 1.1.6 (Safety → Objectionable Content)** — apps that enable "stalking or harassment". Solved by consent framing.

If rejected, respond with:

> LastSeen positions itself as a family / self monitoring tool. The onboarding flow includes a hard-blocking consent screen (see attached video) requiring users to confirm they will only track accounts they own or have permission to monitor. The app does not collect, sell, or share third-party data; tracked numbers' presence data is only visible to the user who added the number.

Attach a screen recording of the onboarding flow showing the consent gate.
