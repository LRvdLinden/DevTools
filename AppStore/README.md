# DevTools – App Store listing (English, en-US)

Everything you need to publish DevTools 1.0.0 in App Store Connect. The texts are also in `metadata/` (fastlane `deliver` layout). The images are in `screenshots/` and `promo/`.

## App information

| Field | Value |
|---|---|
| Name (max 30) | `DevTools – Developer Dashboard` |
| Subtitle (max 30) | `Releases, TestFlight & Sales` |
| Bundle ID | `nl.lrvdlinden.devtools` |
| SKU | `DEVTOOLS` |
| Primary language | English (U.S.) |
| Primary category | **Developer Tools** |
| Secondary category | **Business** |
| Content rights | Does not contain third-party content |
| Age rating | **4+**: answer "None" to every question; no unrestricted web access |
| Copyright | `2026 PixelForges` |
| Price | Your choice (for example Free, or a paid tier) |

If "DevTools – Developer Dashboard" is already taken, use one of these alternatives: `DevTools: Dev Dashboard`, `DevTools – App Dashboard` or `DevTools by PixelForges`.

## Version 1.0.0

| Field | File |
|---|---|
| Promotional text (170) | `metadata/en-US/promotional_text.txt` |
| Description (4000) | `metadata/en-US/description.txt` |
| Keywords (100) | `metadata/en-US/keywords.txt` |
| What's New | `metadata/en-US/release_notes.txt` (not shown for the first version) |
| Support URL | https://lrvdlinden.github.io/DevTools/support.html |
| Marketing URL | https://lrvdlinden.github.io/DevTools/ |
| Privacy Policy URL | https://lrvdlinden.github.io/DevTools/privacy.html |

## App Review information

- **Sign-in required:** No. Choose "Sign-in not required". The app uses the user's own API key and has a built-in **demo mode**.
- **Notes:** paste `metadata/review_information/notes.txt`.
- **Contact:** your name, phone number and email.

## App Privacy (nutrition label)

- Select **Data Not Collected**. DevTools has no analytics or tracking, and no servers of its own.
- Privacy Policy URL: see above.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is set in `Info.plist`. The app only uses HTTPS and CryptoKit signing, which is exempt, so App Store Connect will not ask about encryption.

## Screenshots (upload per device size)

| App Store Connect slot | Folder | Size |
|---|---|---|
| iPhone 6.9" Display (required) | `screenshots/iPhone-6.9in_1320x2868` | 1320 × 2868 |
| iPhone 6.5" Display (optional) | `screenshots/iPhone-6.5in_1284x2778` | 1284 × 2778 |
| iPad 13" Display (required, the app supports iPad) | `screenshots/iPad-13in_2064x2752` | 2064 × 2752 |
| Apple Watch (required, the app has a Watch app) | `screenshots/AppleWatch-Ultra_422x514` | 422 × 514 |

The order is the file name order (01, 02, …). The screenshots were taken in the iOS 26 simulator with the app's demo mode, so they show real app screens.

## Promo

- `promo/AppIcon-1024.png`: the App Store icon. Xcode supplies it automatically from the asset catalog.
- `promo/Promo-1920x1080.png`: banner for your website or social media.
- `promo/Promo-Square-1080.png`: square image for social media.

## GitHub Pages (support and privacy URLs)

The pages are in `docs/`. Turn them on once:

1. Open **GitHub → LRvdLinden/DevTools → Settings → Pages**.
2. Under Source, choose **Deploy from a branch**, then branch **main** and folder **/docs**, and save.
3. After about one minute the pages are live at https://lrvdlinden.github.io/DevTools/.

## Extra mock-up screenshots

The folders `iPhone-6.9in-1320x2868`, `iPhone-6.3in-1206x2622`, `iPad-13in-2064x2752`, `AppleWatch-*` and `Promo/` contain marketing mock-ups with captions (generator in `_generator/`). They are an alternative to the real simulator screenshots of the demo mode.
