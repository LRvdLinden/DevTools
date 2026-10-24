# DevTools push relay

A small Cloudflare Worker between **App Store Connect webhooks** and **OneSignal**. It stores nothing.

```
App Store Connect ──(signed webhook)──▶ Worker /hook/<deviceKey> ──▶ OneSignal ──▶ iPhone
DevTools app ──(APNs token + random deviceKey)──▶ Worker /register ──▶ OneSignal user (external_id = deviceKey)
```

- `/register` links the device's APNs token to OneSignal. It returns the webhook URL plus a per-device secret: `HMAC(HOOK_SECRET, deviceKey)`.
- `/hook/<key>` checks `X-Apple-SIGNATURE` (`hmacsha256=<hex>` over the raw body), builds a localized message and sends it to that one device only.
- In-between states (for example builds that are still processing) are skipped.

## Setting up once

1. **OneSignal**
   1. Create a new app, platform **Apple iOS (APNs)**.
   2. Upload a **.p8 APNs auth key**. You create it at developer.apple.com → Keys → `+` → Apple Push Notifications service. Use Team ID `EU3UY476T6` and bundle ID `nl.lrvdlinden.devtools`.
   3. Write down the **App ID** and the **REST API key**, both under Settings → Keys & IDs.
2. **Cloudflare**
   1. In Workers & Pages, create an API token using the "Edit Cloudflare Workers" template.
   2. Write down your **Account ID**.
3. **GitHub repo → Settings → Secrets and variables → Actions:** add these secrets:

   | Secret | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token from step 2 |
   | `CLOUDFLARE_ACCOUNT_ID` | your Account ID |
   | `ONESIGNAL_APP_ID` | the App ID |
   | `ONESIGNAL_REST_KEY` | the REST API key |
   | `HOOK_SECRET` | a long random string, e.g. `openssl rand -hex 32`. Never change it, or existing webhooks stop working. |

4. **Deploy.** Go to Actions → *Deploy push relay* → Run workflow, or push a change in `push-relay/`. The URL becomes `https://devtools-push.<your-subdomain>.workers.dev`.
5. **App.** In `DevTools/Info.plist`, set `DevToolsPushRelay` to that URL. Push Notifications is already in the entitlements, and Xcode turns the capability on for the App ID automatically.
6. **App Privacy** (App Store Connect): **Identifiers → Device ID**, used for App Functionality, not linked to the user, no tracking.

Without `wrangler`, you can also paste `src/index.js` into the Cloudflare dashboard (Workers → Create → Edit code) and set the three secrets under Settings → Variables.

## Tests

```
cd push-relay && node --test test/relay.test.js
```
