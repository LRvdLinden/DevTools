# DevTools 1.0.0 (Build 1)

Native SwiftUI **App Store Connect companion** for iPhone, iPad and Apple Watch. Inspired by the architecture (not assets/branding) of `LRvdLinden/Athom-Homey-dev-ios`.

## Implemented now

- Multiple API accounts with `.p8` imported into local iOS Keychain
- Official ES256 JWT authentication and App Store Connect `/v1/apps` API
- Live apps, per-app versions/builds, review-state, and customer reviews
- Responsive iPhone tab navigation and iPad sidebar, system/light/dark appearance
- Home screen widgets (portfolio, review), paired Apple Watch overview and complications
- Refresh on launch/manual pull, explicit network errors; no fictitious analytics

## Not yet live in this build

- Sales/downloads/proceeds/subscriptions: require Apple's reports API, scheduling, parsing and refresh pipeline. The Insights screen explains the limitation.
- Real push: requires server/webhook subscriber and APNs/OneSignal credentials; no push claim is made in UI.
- AI: interface and local release-note draft/export only; requires explicit choice of model/backend and secure key management.
- Review reply actions and editable release metadata: read-only until write scopes, validation and safe confirmation UI are implemented.
- Watch receives latest data from paired phone via WatchConnectivity, not direct Apple login.
- Localization: native source strings prepared; English text currently used. Dutch/German/French catalogs are future work.

## Setup

1. Open `DevTools.xcodeproj` in Xcode 16+.
2. Select your Apple signing Team for **all four targets** (iPhone, widget, Watch app, Watch complication).
3. Adjust bundle identifiers if already taken and configure App Groups `group.nl.lrvdlinden.devtools` where appropriate.
4. Create an App Store Connect API key with appropriate **read** access in Users and Access. Import its downloaded `.p8` file in Account > Add Apple Developer Account.
5. Run the iPhone app and pair Apple Watch. Watch updates via WatchConnectivity when the phone sends its snapshot.

**Important:** Never commit API keys, login credentials, or `.p8` files. Private key is stored as device-only Keychain data. Server-side token storage is not implemented in this starter.

## Security

JWT expires after 15 minutes and is generated on demand using CryptoKit P256 ECDSA. Network requests use HTTPS. Use least-privilege API keys. A public multi-tenant production release needs threat modelling, privacy policy, audit of API key handling, backend availability/retention rules, and API endpoint coverage tests.


## Build 2 — iPhone and Apple Watch scheme fix

In Xcode choose the **DevTools** scheme and an **iPhone simulator or connected iPhone** (not My Mac). For the watch app choose **DevToolsWatch** and a **paired Apple Watch simulator**. If no iPhone devices appear, install the iOS Simulator runtime under Xcode > Settings > Platforms. If no Apple Watch device appears, install the watchOS Simulator runtime and pair one to an iPhone simulator. This release adds shared Xcode schemes, explicit iOS/watchOS supported platforms, and shared Watch widget storage. On physical devices set a valid Apple Developer Team for every target and configure both App Groups. macOS is not a target.

## Build 6 changes
- Fix SwiftUI `foregroundStyle` ternary type mismatch in `Screens.swift` line 211 (`Color.secondary` / `Color.green`).
- Keep automatic signing team `EU3UY476T6` for all four targets.
- This source was syntax-checked with Swift parser and plist-validated on Linux. Full Xcode compilation needs macOS.

## Build 8 fixes
- Full-bleed Concept A 1024px icon installed for iOS and watchOS; Apple masks the app icon corners.
- Main iOS target `SKIP_INSTALL=NO`; Watch and both WidgetKit extensions `SKIP_INSTALL=YES` in Debug and Release to avoid generic archives.
- Archive using the **DevTools** scheme and **Any iOS Device (arm64)**, not the Watch scheme.
- Apple Developer Team: EU3UY476T6.
- This was statically validated; the Xcode archive must be verified on macOS.
