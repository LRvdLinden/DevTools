# Changelog

## 1.0.0 (build 15)
Everything the App Store Connect API offers is now in DevTools. Per app, under *Manage* in the app detail screen:

- **App Analytics:**
  - What you see: impressions, product page views, conversion, first-time downloads and redownloads, sessions with average duration, active devices, crashes, deletions, and day 1 / day 7 retention.
  - Includes a chart and a choice of 7, 14 or 30 days.
  - DevTools turns on Apple's ongoing analytics reports once; the first reports arrive after 1–2 days. Instances are cached locally.
  - Apple has no retention report, so retention is approximated from sessions of new users.
- **Phased release:**
  - Turn it on before release and follow the 7 days (1–100%).
  - Pause or resume it, or release to everyone right away.
  - Located on the version screen.
- **TestFlight feedback and crashes:**
  - Screenshots and comments from testers, with device, OS, battery, connection and free storage.
  - Crash logs that you can share or copy; feedback can be deleted.
  - **Reply by email** to the tester. Apple has no reply option for TestFlight feedback, so your mail app opens with the comment quoted.
  - Per app, and per build from the build screen.
  - **Diagnostics** per build: hangs, launches and disk writes, with call stacks.
- **Screenshots and previews:**
  - View, upload (from Photos), reorder and delete, per language and per screen size.
  - Add new screen sizes. Previews (video) can be uploaded too.
  - **Header and Search Results images** are placed through Apple's Asset Library, on the version screen.
- **Price and availability:**
  - Base price and your proceeds, prices per country, and changing the price through Apple's price points.
  - Turn availability on or off per country.
- **In-app purchases and subscriptions:**
  - List, create (IAP) and edit them: family sharing, review note, display name and description per language.
  - Submit for review.
  - **Offer codes:** generate one-time codes and download or share them as CSV; custom codes are listed. Apple replaced IAP promo codes with offer codes on 26 March 2026; app promo codes are only available in App Store Connect.
- **Xcode Cloud:** workflows, build runs with commit, duration and actions (errors, warnings, test failures), and **starting a build** on a branch or tag of your choice.
- **Webhooks:** create, turn on or off, choose events, send a ping, and view and resend deliveries. This also works for a Homey or Slack URL.
- **Push notifications (OneSignal SDK 5.8.0 with Notification Service Extension):**
  - Account → Push notifications → turn on for all apps.
  - DevTools creates a webhook per app that points to the DevTools push relay (Cloudflare Worker, `push-relay/`). The relay checks Apple's signature and sends the notification through OneSignal in your language.
  - Notifications cover versions entering review, being approved, rejected or going live, builds being ready or failing, external TestFlight, and new feedback or crashes.
  - Your API key never leaves the device. Set it up once following `push-relay/README.md`.
- **Team and development** (Account): users and roles (edit, remove), invitations, certificates (revoke), identifiers (create), devices (register, turn on/off) and provisioning profiles.
- **More:** in-app events, custom product pages (visibility, copy link), A/B tests of your product page with variants, and Game Center leaderboards and achievements.
- **TestFlight installs** per app and per build, with testers, sessions, crashes, feedback and invites, on the TestFlight tab, the app detail screen and the dashboard.
- All new screens are in all 9 languages, and the privacy policy is updated for the optional push notifications.

## 1.0.0 (build 14)
- **English is the default.** If the device language is not supported, the app shows English.
- **9 languages:** English, Dutch, German, French, Spanish, Polish, Norwegian, Danish and Swedish. They cover the app, widgets and Apple Watch, with 407 strings per language.
- **Language picker in Account → Appearance:** choose *Automatic* (follows the device) or a fixed language. The change takes effect immediately. Widgets and the Apple Watch follow the same choice.
- You can also change the language via iOS Settings → DevTools → Language.
- Translations live in `Shared/Localization/i18n/*.json`. `translations.py` generates every `.lproj`.
- Build for App Store submission, with demo mode for App Review and `ITSAppUsesNonExemptEncryption = NO`.
- The App Store metadata from build 13 has been restored: review notes for the demo mode and links to GitHub Pages.

## 1.0.0 (build 13)
- **The app is now in English and Dutch.** It follows the device language, using 400+ translated strings, and covers the app, widgets and Watch.
- **Demo mode** ("Try the demo" on the welcome screen) shows sample data with no API key needed. App Review uses it, and it also produces the App Store screenshots. You can exit the demo under Account.
- **App Store listing** in `AppStore/`: English screenshots for iPhone 6.9" and 6.5", iPad 13" and Apple Watch Ultra, promo images, and the name, subtitle, description, keywords, promotional text, review notes and privacy answers.
- A **support, privacy and landing page** is in `docs/`, ready for GitHub Pages.
- `ITSAppUsesNonExemptEncryption = NO` is now in Info.plist, so App Store Connect no longer asks the export compliance question.
- The splash screen background is now fully opaque.
- The Apple Watch Fetch button has moved onto the overview page.
- A GitHub Actions workflow takes screenshots automatically in the iOS, iPad and watchOS simulators. Add `[shots]` to the commit message to run it.

## 1.0.0 (build 12)
- **Apple Watch app rebuilt in the HomeyDev style.** It has three vertical pages:
  - *Overview:* downloads with the 7-day change, a chart, and Live / In review / Proceeds / Rating.
  - *My apps:* each app with its real icon, downloads, trend and status dot, and a detail screen.
  - *Attention:* apps in review, apps that need attention, and builds missing export compliance.
- An **Ophalen** (Fetch) button asks the iPhone for fresh data. The app icons are copied to the watch as well.
- **Complication** like the one in HomeyDev: downloads, the 7-day change, live count and apps in review (circular, corner, inline and rectangular).
- **Widgets rebuilt in the HomeyDev style:**
  - *Downloads* (S/M/L): choose one app or all apps under Edit widget. It shows a Homey Insights chart with min/max and a dot on the latest value, the 7-day change, proceeds, rating and updates.
  - *Top apps* (M/L): icon, sparkline, downloads, change, version, rating and status.
  - *Review & status* (S/M/L): Live, In review, Rejected, Rating, and lists of apps in review and apps that need attention.
- **Handleiding (guide) in Account:** step-by-step instructions for creating an API key, the Issuer ID, the Key ID, downloading the .p8, finding the vendor number (Business), which role you need, security, and troubleshooting 401/403. It is also linked from the add-account screen and the welcome screen.
- The snapshot for widgets and the watch now holds daily downloads per app, rating, proceeds, updates and build status.

## 1.0.0 (build 11)
- Only **Ready for Sale** now counts as **Live**. **Ready for Distribution** gets its own status, "Klaar voor distributie" (cyan): the step before going live. This applies in the app, the widgets and on the Watch.
- Version status is now read from Apple's `appStoreState`, which is the only field that says READY_FOR_SALE once a version is actually live.
- The help text and link for the vendor number now point to App Store Connect → **Business**.

## 1.0.0 (build 10)

### New
- **Splash screen:** new animation with an aurora background, particles, a 3D icon drop, orbit rings, a letter-by-letter title, an animated chart line and a live progress bar during the first data load. Also added to the Apple Watch.
- **App icons:** your apps' real icons everywhere, including in the widgets.
- **Live status:** *Ready for Sale* and *Ready for Distribution* are now shown as **Live**. All App Store and TestFlight states have Dutch labels and colours.
- **Downloads and proceeds** per app and in total via Sales Reports (vendor number per account). Choose 7d, 30d, 90d or 1 year.
- **Charts** in the Homey Insights style: gradient area with a line, scrubbing, min/average/max, per-app lines, a countries list and a devices donut.
- **New App Store version:** create one, edit What's New, description, keywords, promotional text and URLs per language, add languages, and copy What's New to all languages.
- Attach a build, submit for App Review, cancel a review, release a version and delete a version.
- App info: name, subtitle and privacy URL.
- **TestFlight:** builds per version, expire a build, export compliance, What to Test, test groups per build, auto-notify and beta review.
- **Test groups:** create groups, public link, invite and remove testers.
- **Reviews:** rating chart, filters, reply, and edit or delete replies.
- Dashboard with an "Attention needed" card, a welcome screen for first launch, and an iPad sidebar with your apps.
- Widgets: Overview (S/M/L), Downloads (sparkline) and App Review.

### Fixed
- Dates with fractional seconds from the API no longer break loading.
- The version in Account is now read from the bundle (it previously showed a fixed "1.0.0 (6)").
- The splash logo no longer has white corners.

### Technical
- The code is split into Core (API, models, store, sales) and Views.
- The API client now supports GET, POST, PATCH and DELETE, reads Apple's error messages, and decompresses gzip reports.
- App data is cached locally so the app starts instantly.
- GitHub Actions now runs an Xcode build check.
- All targets are on build number 10.

## 1.0.0 (build 9)
- App Store Connect validation fixes (launch screen, iPad orientations, widget display name).
