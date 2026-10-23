# DevTools

Native SwiftUI **App Store Connect companion** for iPhone, iPad and Apple Watch, in the style of HomeyDev (Homey Developer Tools). It is built on the official [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi).

**Version 1.0.0 (build 14)** · English + Dutch · Team `EU3UY476T6` · Bundle `nl.lrvdlinden.devtools`

## Features

| Area | What you can do |
|---|---|
| **Splash** | Animated launch screen with aurora background, particles, the icon dropping in with a 3D tilt, orbit rings, a letter-by-letter title, an animated chart line, and a progress bar that follows the real data load. Respects Reduce Motion. |
| **Home** | Greeting, KPI tiles (installs, proceeds, live, in review, updates, average rating), a Homey Insights-style trend chart with 7d/30d/90d/1y, downloads per app, an "Attention needed" card and app list with icons |
| **Apps** | Real app icons (App Store artwork, or the icon from the latest build). Status badges: only *Ready for Sale* shows as **Live**; *Ready for Distribution* shows as **Ready for distribution** (the step before going live). Filters (Live, In review, Preparing, Rejected), sorting and search |
| **App detail** | Downloads trend, top countries, versions, latest builds, reviews, app info and test groups |
| **Versions & texts** | Create a new App Store version, edit What's New, description, keywords, promotional text and URLs per language (copy What's New to all languages in one go), add languages, version settings (copyright, release type, scheduled date), attach a build, **submit for App Review**, cancel a review, release a version, delete a version |
| **App info** | Name, subtitle and privacy policy URL per language |
| **TestFlight** | All builds per version, expire a build (swipe), export compliance, What to Test per language, add builds to or remove them from test groups, auto-notify, submit for beta review |
| **Test groups** | Create internal/external groups, enable public link and share it, add testers (email invite) and remove them, delete groups |
| **Reviews** | Rating distribution chart, filter by stars or unanswered, reply to reviews and edit or delete replies |
| **Insights** | Installs, new downloads, re-downloads, updates, in-app purchases and proceeds. Trend chart with scrubbing, installs per app over time (top 5), proceeds per app, countries with flags, devices donut, status of all apps |
| **Widgets** | Same layout as HomeyDev: *Downloads* (pick one app or all apps, Insights chart), *Top apps* (icons, sparklines, change), *Review & status* |
| **Apple Watch** | Same layout as HomeyDev: vertical pages *Overview*, *My apps* (with icons) and *Attention*, a Fetch button and an app detail screen. Complications show downloads, change, live and in review |
| **Guide** | Account → Guide: how to get the API key, Issuer ID, Key ID, .p8 and vendor number, which roles you need, and troubleshooting |
| **Accounts** | Multiple API keys, account switcher, vendor number per account, light/dark/system theme |

## Publishing

Everything for the App Store listing is in [`AppStore/`](AppStore/README.md): screenshots, promo images and all texts. The support and privacy pages are in `docs/` (GitHub Pages).

## Setup

1. Open `DevTools.xcodeproj` in Xcode 16 or newer (CI builds with Xcode 26.6).
2. The team for all four targets is `EU3UY476T6`, with App Groups `group.nl.lrvdlinden.devtools` and `group.nl.lrvdlinden.devtools.watch`.
3. In App Store Connect, go to **Users and Access → Integrations → App Store Connect API** and create a team key. Give it the **Admin** role, or **App Manager + Sales**, to use every feature.
4. In the app, open **Link account**. Fill in the Issuer ID, choose the `AuthKey_XXXX.p8` file (the Key ID is filled in automatically) and enter your **vendor number**. You find the vendor number on the **Business** page, next to your address.
5. To archive, use the **DevTools** scheme with **Any iOS Device (arm64)**.

## How data is retrieved

- **Apps, versions, builds, TestFlight, reviews** come from `api.appstoreconnect.apple.com/v1/...` with an ES256 JWT (valid for at most 20 minutes, signed with CryptoKit).
- **Downloads and proceeds** come from `GET /v1/salesReports` (SALES · SUMMARY · DAILY/WEEKLY, version 1_0). The reports are gzip-decompressed and parsed as TSV, then cached per day in the app's Caches folder. Apple's data runs about one day behind.
  - Downloads are product types `1, 1F, 1T, F1`. Re-downloads are `3*`, updates `7*` and in-app purchases `IA*`.
- **Icons and ratings** come from App Store artwork via the iTunes Lookup API for live apps, or from the `iconAssetToken` of the latest build.

> Builds themselves are still uploaded from Xcode or Transporter. Apple's API has no endpoint for uploading binaries. DevTools takes over everything after the upload.

## Security

- The `.p8` private key is stored only in the Keychain (`ThisDeviceOnly`) and is never synced or committed.
- Never commit API keys or `.p8` files (`.gitignore` excludes `*.p8`).

## CI

`.github/workflows/build-check.yml` builds the project unsigned on every push, using `macos-latest`, the DevTools scheme and a generic iOS device, so the watch app and widgets are built too. The result is written to the `ci-logs` branch.

See [CHANGELOG.md](CHANGELOG.md) for all changes.

© DevTools - PixelForges · Independent app, not affiliated with Apple.

## App Store

Screenshots (EN), promo images and all listing texts are in [`AppStore/`](AppStore/README.md). See also the [Privacy Policy](PRIVACY.md) and [Support](SUPPORT.md).
