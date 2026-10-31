# App Store Connect for Homey

`nl.lrvdlinden.appstoreconnect` · v1.1.0 · Homey Pro (local) · SDK 3 · Homey ≥ 12.3.0 · 13 languages (en, nl, de, fr, it, sv, no, es, da, ru, pl, ko, ar)

This app brings App Store Connect into Homey, with the same design as the DevTools iPhone app. It is inspired by *App Insights for Developers*, but for Apple's App Store instead of the Homey App Store.

## Devices

### App Store app (one per app)

| Capability | Description |
|---|---|
| Downloads yesterday / 7 days / 30 days / total | New downloads plus re-downloads, from Apple Sales Reports. Insights is enabled. |
| Updates 30 days, Proceeds 30 days | Proceeds are in your payout currency. |
| App Store status | Live (Ready for Sale), Ready for Distribution, Waiting for Review, In Review, Pending Release, Rejected, … |
| In App Review | Boolean (yes/no) |
| Live version, Next version | |
| Latest build, Build status | TestFlight status |
| Rating, Ratings | From the public App Store |
| TestFlight installs, TestFlight testers | Sum of all builds (`betaBuildUsages`), refreshed every few hours. Insights is enabled. |
| Phased release | Waiting for release, Active · 5%, Paused, Released to everyone |

### All apps (portfolio)

Shows the same totals as above, plus the number of apps, live apps, apps in review and apps that need attention, and the TestFlight installs of all apps.

## Flows

**Triggers (per device)**
- Status changed
- Entered App Review
- Rejected
- Ready for distribution
- Waiting for your release
- New live version
- New build
- Build processed
- New customer review (with the review ID token for replying)
- Rating changed
- New download figures
- Downloads dropped
- New TestFlight feedback, new TestFlight crash report (comment, tester, device, OS version, build)
- Phased release changed (status, day, percentage)
- Xcode Cloud build finished (workflow, number, result, succeeded)

**Triggers (app level)** fire for any app, with an App token:
- Status changed
- Entered review
- Rejected
- New live version
- New review
- Total downloads updated
- New TestFlight feedback, new TestFlight crash report

**Conditions**
- Is live
- In App Review
- New version in progress
- Downloads yesterday, last 7 days or total are above a value
- Rating above a value
- Live version older than X days
- Phased release in progress
- TestFlight installs above a value
- For all apps: downloads above a value, any app in review

**Actions**
- Refresh
- Release the approved version (Pending Developer Release)
- Reply to a customer review
- Control the phased release: pause, resume, or release to all users
- Start an Xcode Cloud workflow (autocomplete)

## Widgets

The widgets use the same design as the DevTools iOS widgets:

- **Downloads:** choose one app or all apps, and the period (yesterday, 7 days, 30 days or all time). It shows an Insights chart with min/max, the 7-day change, rating, proceeds, updates and the total.
- **Top apps:** each app's icon, name and status, a sparkline, its downloads and the change.
- **Review & status:** counts of Live, In review and Attention apps, plus lists.

## Setup

1. In App Store Connect, go to Users and Access → Integrations → App Store Connect API → Team Keys and create a key with the **Admin** role.
2. In the app settings, fill in the Issuer ID, Key ID, the contents of the `.p8` file and your vendor number. You find the vendor number under App Store Connect → **Business**.
3. Add devices.

## Translations

The whole app is translated into every Homey language: the app name, description and tags, capabilities, flow cards, devices, widgets, the settings page, status labels and the store text (`README.<lang>.txt`).

- `python3 tools/i18n.py extract` collects every string into `i18n/source.json`.
- Translations go in `i18n/<lang>.json`. `python3 i18n/check.py i18n/<lang>.json` checks placeholders and Flow syntax.
- `python3 tools/i18n.py apply` writes them back into the compose files, `locales/` and the READMEs.

## Technical notes

- No dependencies. The ES256 JWT is signed with Node `crypto`, and the gzip Sales Reports are unpacked with `zlib`.
- The app checks status every 15 minutes (adjustable) and downloads every 3 hours. Apple publishes yesterday's figures once a day.
- Reports for closed periods are cached in `/userdata/sales`. All-time totals are built from yearly, monthly and daily reports.
- `npm test` runs offline tests: JWT, report parsing and aggregation, plus a full app run with a mocked Homey that checks triggers and conditions.

© PixelForges · Not affiliated with Apple Inc.
