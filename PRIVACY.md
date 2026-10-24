# DevTools – Privacy Policy

_Last updated: October 24, 2026_

DevTools ("the app") is published by PixelForges. This policy explains what happens to your data when you use the app on iPhone, iPad and Apple Watch.

## Summary

**DevTools does not collect, store or share any personal data.** The app contains no analytics, advertising or tracking. Only if you turn on the optional push notifications, a push token and a random device ID are passed to our push relay and OneSignal (see below).

## What the app processes, on your device only

- **App Store Connect API key.** You enter your Issuer ID and Key ID and import your private key (.p8). The private key is stored only in the iOS Keychain on your device, with the setting "this device only". It is never synced, uploaded or shared. The Issuer ID, Key ID, account name and vendor number are stored in the app's local settings.
- **App Store Connect data.** The app requests your apps, versions, builds, TestFlight information, customer reviews and sales reports directly from Apple's App Store Connect API (`api.appstoreconnect.apple.com`), using your own key. This data is shown in the app and cached temporarily on your device to speed up launching. It is never sent to us or to any third party.
- **App icons and ratings.** To show app icons and public ratings, the app uses Apple's public iTunes Search API (`itunes.apple.com`) with the numeric App Store IDs of your apps.
- **Widgets and Apple Watch.** A summary of your data, such as app names, status and download counts, is shared with the app's widgets through an App Group on your device. It is sent to your paired Apple Watch through Apple's WatchConnectivity framework.

## Optional push notifications

Push notifications are off by default. If you turn them on (Account → Push notifications):

- Your device's Apple push token and a random ID created by the app (not linked to your name, e-mail, Apple ID or App Store Connect account) are sent to the DevTools push relay, a Cloudflare Worker run by PixelForges, which registers them with OneSignal, our push provider.
- The app creates a webhook in your App Store Connect account for each app. When something changes (for example a version goes live, a build is processed or a tester sends feedback), Apple sends a signed event to the relay. The relay checks Apple's signature and asks OneSignal to show a notification on your device. The relay stores nothing; the event is only used to compose the notification text.
- Your API key never leaves your device.
- Turning push notifications off removes the webhooks. You can also delete them in App Store Connect → your app → Webhooks.

OneSignal's privacy policy: https://onesignal.com/privacy_policy. Cloudflare's privacy policy: https://www.cloudflare.com/privacypolicy/.

## Third parties

Apart from the optional push notifications above, the app communicates only with Apple services. Apple's handling of data is described in [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

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
