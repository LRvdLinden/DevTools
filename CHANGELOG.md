# Changelog

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
