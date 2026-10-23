# DevTools – Privacy Policy

_Last updated: October 23, 2026_

DevTools ("the app") is published by PixelForges. This policy explains what happens to your data when you use the app on iPhone, iPad and Apple Watch.

## Summary

**DevTools does not collect, store or share any personal data.** We have no servers, and the app contains no analytics, advertising or tracking.

## What the app processes, on your device only

- **App Store Connect API key.** You enter your Issuer ID and Key ID and import your private key (.p8). The private key is stored only in the iOS Keychain on your device, with the setting "this device only". It is never synced, uploaded or shared. The Issuer ID, Key ID, account name and vendor number are stored in the app's local settings.
- **App Store Connect data.** The app requests your apps, versions, builds, TestFlight information, customer reviews and sales reports directly from Apple's App Store Connect API (`api.appstoreconnect.apple.com`), using your own key. This data is shown in the app and cached temporarily on your device to speed up launching. It is never sent to us or to any third party.
- **App icons and ratings.** To show app icons and public ratings, the app uses Apple's public iTunes Search API (`itunes.apple.com`) with the numeric App Store IDs of your apps.
- **Widgets and Apple Watch.** A summary of your data, such as app names, status and download counts, is shared with the app's widgets through an App Group on your device. It is sent to your paired Apple Watch through Apple's WatchConnectivity framework.

## Third parties

The app communicates only with Apple services. Apple's handling of data is described in [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## Deleting your data

- Remove an account in the app (Account → swipe → Delete). This deletes the key from the Keychain and the cached data.
- Deleting the app removes all local data.
- You can also revoke the API key at any time in App Store Connect → Users and Access → Integrations.

## Children

The app is intended for software developers and does not knowingly process data from children.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions? Open an issue at https://github.com/LRvdLinden/DevTools/issues.
