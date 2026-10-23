# DevTools

Native Apple developer companion for **iOS, iPadOS and watchOS** (SwiftUI), designed after the architecture of [Homey Developer Tools for iOS](https://github.com/LRvdLinden/Athom-Homey-dev-ios).

## Status

Version 1.0.0, build 2 (development). The corrected Xcode project currently exists as a downloadable ZIP in the ChatGPT conversation. This repository is not yet a complete source mirror.

## Intended targets

- `DevTools` — iOS 17+ / iPadOS 17+
- `DevToolsWidgets` — iPhone and iPad widgets
- `DevToolsWatch` — watchOS 10+
- `DevToolsWatchWidgets` — Apple Watch complications

Bundle IDs use `nl.lrvdlinden.devtools` and appropriate suffixes.

## Current features and limitations

App Store Connect API-key sign-in, app and build lists, reviews, dashboards, basic widgets, Watch overview and complications are implemented as a first development pass. Downloads, revenue, subscriptions, production push and AI model integrations require further work. No Xcode build has been run yet.

The build 2 archive corrects a missing target-build-settings generation bug in build 1; it explicitly sets `iphoneos iphonesimulator` and `watchos watchsimulator`, adds shared schemes and Watch group entitlements.

**Never commit App Store Connect `.p8` private keys.**
