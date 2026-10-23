# DevTools – Support

DevTools is a companion app for App Store Connect on iPhone, iPad and Apple Watch.

## Getting started

1. In App Store Connect, go to **Users and Access → Integrations → App Store Connect API → Team Keys** and create a key. Give it the **Admin** role so you can use every feature.
2. Copy the **Issuer ID** shown above the list of keys.
3. Download the **AuthKey_XXXXXXXXXX.p8** file. Apple only lets you download it once. The part after `AuthKey_` is your **Key ID**.
4. In DevTools, tap **Link App Store Connect**, enter the Issuer ID and import the .p8 file. The Key ID is filled in automatically.
5. To see downloads and proceeds, add your **vendor number**. You find it in App Store Connect → **Business**, next to your address.

The app also has a built-in step-by-step guide under **Account → Guide**.

## Which role does my key need?

| Feature | Role |
|---|---|
| Apps, versions, texts, builds, TestFlight | App Manager or Admin |
| Downloads and proceeds (Sales Reports) | Sales, Finance or Admin |
| Replying to reviews | Customer Support, App Manager or Admin |

## Troubleshooting

- **401 – Authentication failed:** the Issuer ID or Key ID is wrong, the .p8 belongs to another key, or the key was revoked.
- **403 – Forbidden:** the key's role does not allow this action.
- **No downloads:** the vendor number is missing or wrong, or the key has no Sales or Finance role. Apple's reports also run about one day behind.
- **No icons:** icons come from the App Store (for live apps) or from your latest uploaded build. Pull down to refresh.
- **Apple Watch shows no data:** open DevTools on your iPhone first, then tap **Fetch** on the watch.

## Contact

Found a bug or have a question? [Open an issue](https://github.com/LRvdLinden/DevTools/issues) and include your iOS version and what you did.

DevTools is an independent app by PixelForges and is not affiliated with Apple Inc.
