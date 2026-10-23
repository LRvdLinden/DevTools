# DevTools — App Store listing (English, en-US)

Everything you need to fill in App Store Connect for version **1.0.0**. All texts are also available as separate `.txt` files in `metadata/en-US/`, so you can copy them directly.

## App information

| Field | Value |
|---|---|
| Name (30) | `DevTools: Developer Dashboard` (29) |
| Subtitle (30) | `Sales, builds, reviews & beta` (29) |
| Primary category | **Developer Tools** |
| Secondary category | **Business** |
| Bundle ID | `nl.lrvdlinden.devtools` |
| SKU | `devtools-ios` (your choice) |
| Primary language | English (U.S.) |
| Copyright | `2026 PixelForges` |
| Content rights | Does not contain, show or access third-party content |
| Price | Free, or your choice |

If the name is already taken, try one of these: `DevTools – Dev Dashboard` · `DevTools for Developers` · `DevTools by PixelForges`.

## Version texts

- **Promotional text (170):** see `promotional_text.txt` (156 characters)
- **Description (4000):** see `description.txt` (about 2,850 characters)
- **Keywords (100):** `asc,connect,downloads,analytics,indie,ios,release,proceeds,revenue,metrics,stats,testers,charts` (95)
  - These avoid words that already appear in the name and subtitle, because Apple indexes those already.
  - Apple trademarks such as "App Store Connect", "TestFlight" and "Xcode" are left out on purpose. Guideline 2.3.7 does not allow other parties' trademarks in keywords.
- **What's New:** see `release_notes.txt`. Apple does not show this for version 1.0, but it is ready for the next version.
- **Support URL:** https://github.com/LRvdLinden/DevTools/blob/main/SUPPORT.md
- **Marketing URL:** https://github.com/LRvdLinden/DevTools
- **Privacy Policy URL:** https://github.com/LRvdLinden/DevTools/blob/main/PRIVACY.md

## Screenshots

| Device | Size | Files |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | 7 (dashboard, app detail, new version, TestFlight, insights, reviews, widgets) |
| iPhone 6.3" | 1206 × 2622 | 7 (same) |
| iPad 13" | 2064 × 2752 | 4 |
| Apple Watch Ultra 3 | 422 × 514 | 4. Upload **one** Watch size. |
| Apple Watch Series 11/10 (alternative) | 416 × 496 | 4 |

- All files are PNG, RGB, without alpha.
- The sample apps in the screenshots (Trailhead, Lumen Notes, …) are fictional demo data.

Promo images (not required, but useful for featuring nominations and socials): `Promo/promo-1920x1080.png` and `Promo/social-1200x630.png`.

## App Privacy ("nutrition label")

- **Data collection:** choose **No, we do not collect data from this app**. The result is **Data Not Collected**.
  - The app has no server, analytics, advertising or tracking.
  - API requests go directly from the device to Apple.
  - Icon and rating lookups go to Apple's public iTunes Search API.
- **Tracking (ATT):** No.

## Age rating

- Answer **None / No** to every question. There is no user-generated content, no web browser, no gambling and no medical information.
- The expected result is **4+**.

## Export compliance (encryption)

- The app uses encryption only via standard HTTPS and Apple CryptoKit, to sign the JWT. This is **exempt**.
- In App Store Connect, answer: "Does your app use encryption?" **Yes**. Does it qualify for any exemptions? **Yes**, standard encryption only.
- Tip: add `ITSAppUsesNonExemptEncryption = NO` to `Info.plist`. Then you no longer get this question for every build.

## App Review: important

- Apple's reviewer needs access, otherwise the app gets rejected under guideline 2.1 (App Completeness / no demo access).
- Choose one of these options:
  1. **Temporary API key** with the role *Developer* (read only, no sales data). Fill in `review_notes.txt` with the Issuer ID, Key ID and a link to the .p8, and revoke the key after approval.
  2. **Demo mode** in the app, so it can be tried with sample data and without a key. This is the most robust option, and can be built in a later build.
- Sign-in required: **No** (there is no username/password). Explain the API key in the Notes instead.

## Localization

The app UI is currently **Dutch**, while this listing is English. Apple allows that, but for an English listing an English UI is clearer for users and reviewers, and the screenshots show the English UI. Recommendation: add an English localization (String Catalog, Dutch + English) before you submit.
