# DevTools v1.0.0 build 9 - App Store Connect validation fixes

Based on Build 8.

## Confirmed Apple validation errors from October 23 2026 logs

- 90475 iPad multitasking launch screen absent
- 90474 iPad multitasking orientations absent
- 90870 iOS 27 SDK launch screen absent
- 90360 widget extension CFBundleDisplayName absent

## Fixes

- Added an explicit `DevTools/Info.plist` for the iOS application with `UILaunchScreen` and supported device orientations.
- Changed main iOS target to `GENERATE_INFOPLIST_FILE = NO` with `INFOPLIST_FILE = DevTools/Info.plist` for Debug and Release.
- Added `CFBundleDisplayName` to the two widget extension plists.
- Incremented all target build numbers to 9; development team EU3UY476T6 retained.
- Kept full-bleed icon, SwiftUI splash screen, iOS/iPadOS, Apple Watch, widgets, and Watch complications.

## Test

Extract to a new folder; open `DevTools.xcodeproj`; choose the iOS `DevTools` scheme and a generic iOS device, then Product > Clean Build Folder and Product > Archive. Before uploading, inspect `DevTools.app/Info.plist` in the archive and confirm `UILaunchScreen`, `UISupportedInterfaceOrientations`, and `UISupportedInterfaceOrientations~ipad`. Inspect `DevToolsWidgets.appex/Info.plist` for `CFBundleDisplayName`.

**Not compiled or uploaded from this environment; Apple validation must be retried on macOS.**
