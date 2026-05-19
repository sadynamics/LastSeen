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

## App Review sign-in (App Store Connect)

App Store Connect collects reviewer credentials in two places:

1. **App Information → App Review Information → Sign-In Information**
   (the two fields literally labelled *Username* and *Password*).
2. **App Review Notes** (the long-form text box below).

We fill all three.

### Sign-In Information

| Field      | Value                                                         |
|------------|---------------------------------------------------------------|
| Username   | `reviewer@lastseen.app`                                       |
| Password   | the current value of `REVIEWER_LOGIN_CODE` (from 1Password)   |

The `username` is logged on the server but otherwise ignored — the
shared secret is the password, validated with a constant-time compare
against `REVIEWER_LOGIN_CODE`. Any non-empty username is accepted; we
standardise on `reviewer@lastseen.app` so the field looks like a real
email to the reviewer.

### App Review Notes

The block below is intended to be **copy-pasted verbatim** into App
Store Connect → App Information → **App Review Information → Notes**
(the long-form text box below the Sign-In Information fields).

Everything outside the blockquote is internal commentary and should
NOT be pasted.

> LastSeen is a family / self monitoring tool for WhatsApp activity.
> Onboarding requires the user to confirm they will only track
> accounts they own or have permission to monitor.
>
> Sign in:
> 1. Complete the brief onboarding (you do NOT need Sign in with Apple).
> 2. On the Sign In screen, tap the small "Sign in" link below the
>    legal text. Enter the Username and Password from the Sign-In
>    Information fields above. Tap Continue.
>
> Test:
> 1. Tap "Add a number" and enter a WhatsApp number you have
>    permission to monitor (your own is easiest). Open WhatsApp on
>    that phone to generate activity — LastSeen updates within ~30s.
> 2. Tap "Add a number" again to see the paywall (Premium gate).
> 3. To free the slot: tap the row → "Remove this number". You can
>    then add a different number with no paywall.
> 4. Settings → "Delete account" wipes the account (Guideline 5.1.1(v)).
>
> Notes: the app does not read messages, contacts, or location, and
> respects WhatsApp's own privacy controls (numbers with last-seen
> set to "Nobody" show limited activity, matching native WhatsApp
> behavior).
>
> Questions: support@lastseen.app

> [!IMPORTANT]
> Submission cycle (the secret can be reused across submissions):
> 1. Take the long-lived `REVIEWER_LOGIN_CODE` from 1Password
>    (initial value was generated with `openssl rand -hex 24`).
> 2. Set it on Railway: `railway service api && railway variables --set "REVIEWER_LOGIN_CODE=…"`.
> 3. Paste the **same** value into the Sign-In Information **Password**
>    field for this build's App Review submission. Username stays
>    `reviewer@lastseen.app`.
> 4. Once the build is approved, **unset** the variable:
>    `railway variables --unset REVIEWER_LOGIN_CODE`.
>
> Unsetting the variable has three effects, all immediate (no app
> resubmission required):
>
> 1. `POST /v1/auth/reviewer` returns `404 NOT_FOUND` for every caller,
>    including ones holding the previously-valid secret.
> 2. `GET /v1/config/public` returns `{ reviewerSignInEnabled: false }`,
>    which the iOS Sign In screen reads on every appearance — the
>    visible **"Sign in"** reviewer link disappears for real users.
> 3. The hidden triple-tap backup gesture still opens the credentials
>    sheet (we keep it as a recovery path for the next submission), but
>    its Continue button just shows "Sign-in not accepted." since the
>    endpoint is closed.
>
> Rotate the secret only if you suspect it leaked publicly. The 192-bit
> hex value plus the per-IP rate limit makes brute force infeasible,
> and unsetting the env var fully revokes access between submissions.

## Anticipated rejection patterns

1. **Guideline 5.1.2 (Data & Privacy → Data Use and Sharing)** — "Apps that collect personal information must allow users to revoke consent." Solved via account deletion.
2. **Guideline 4.0 (Design → Spam)** — "Apps that fail to enforce reasonable limits on … user interaction." Solved by onboarding consent + default-off intrusive notifications.
3. **Guideline 1.1.6 (Safety → Objectionable Content)** — apps that enable "stalking or harassment". Solved by consent framing.

If rejected, respond with:

> LastSeen positions itself as a family / self monitoring tool. The onboarding flow includes a hard-blocking consent screen (see attached video) requiring users to confirm they will only track accounts they own or have permission to monitor. The app does not collect, sell, or share third-party data; tracked numbers' presence data is only visible to the user who added the number.

Attach a screen recording of the onboarding flow showing the consent gate.
