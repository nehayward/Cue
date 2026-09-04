# Super Day

A free 24-hour pass to everything in Cue Super, once every 30 days. Sells the whole bundle at the moment someone hits a gate — the download limit, a locked room, a Live Activity — instead of arguing for one feature at a time. Pairs with the free download limit (`DownloadManager.freeSongLimit`): the "50 free downloads used" banner is a natural place for "Try Super free for a day".

## Approach

Grant the pass **server-side as a RevenueCat promotional entitlement**, through the existing backend at `api.cue.dance` (the newsletter endpoint lives there — see `NewsletterKit`). A promotional grant arrives through the same `customerInfoStream` a real purchase does, so every existing gate — the app's `subscription.isActive` checks, and the synced `CloudKeys.hasSubscription` flag that widgets, Watch, and Cue Mini read — lights up with no new client checks. Expiry is automatic.

## Flow

1. **Client** — "Try Super free for a day" button on `CuePaywall` and on locked states (the download-limit banner, the locked-room card). Posts `SubscriptionService.shared.userID` (the RevenueCat app user ID) and `UIDevice.current.identifierForVendor` to `POST https://api.cue.dance/super-day`.
2. **Server** (Worker + KV) — look up the last grant for either id. Under 30 days old: return `429` with `nextEligibleAt`. Otherwise call RevenueCat `POST /v1/subscribers/{app_user_id}/entitlements/{entitlement}/promotional` with `{"duration": "daily"}` using the secret key (never shipped in the app), record the timestamp under both ids, return `expiresAt`.
3. **Client** — `Purchases.shared.invalidateCustomerInfoCache()` then `checkSubscription()`. The subscription flips, the paywall dismisses, and a confirmation says "Super is yours until 9:14 PM tomorrow".
4. **During the day** — the Cue Super row in `PreferenceScreen` reads "Super Day · ends in 6h". `SubscriptionInfo` already carries `store == .promotional` and `expirationDate`, so nothing new needs storing.
5. **After** — next launch shows one "Keep Super" sheet with the annual price and trial. Live Activities and extra rooms simply stop being offered; nothing is deleted.

## Required first: fix the activity check

`SubscriptionService` (`setup()`, `monitorChanges()`, `checkSubscription()`) decides activity from `customerInfo.activeSubscriptions` and then `nonSubscriptions`. A promotional grant may land in neither. Switch all three to the entitlements dictionary — `customerInfo.entitlements.active[<entitlement id>]` — which is RevenueCat's recommended check and covers subscriptions, lifetime, and promotional in one place. Do this before anything else; it's also a correctness fix for lifetime purchases made through promotional/Stripe stores.

## Abuse

The RevenueCat id is anonymous and resets on reinstall, so the vendor id is the second key. That closes the casual case. If it ever matters, `DeviceCheck` (two per-device bits, server-verified) is the proper fix and the server is already the right place for it. A once-a-month freebie isn't worth defending harder.

## Analytics

- `superDayStarted` — grant succeeded.
- `superDayConverted` — a purchase within 7 days of a Super Day (compute server-side from the grant timestamp and RevenueCat's purchase webhook, or client-side from `SubscriptionInfo.originalPurchaseDate`).
- `viewedPaywall` already accepts `source` metadata (`downloads` is wired); add `superDayEnded` as a source for the "Keep Super" sheet.

## Client-only fallback

Without touching the server: store an expiry `Date` in iCloud KVS (`com.cue.superDayUntil`) and OR it into `isActive`, and have widgets check the date beside `hasSubscription`. Works across devices, but has no reinstall limit and is spoofable, so treat it as a stepping stone.

## Files

| Action | File |
|--------|------|
| Modify | `Packages/SubscriptionKit/.../SubscriptionService.swift` — entitlements-based activity check; `startSuperDay()` calling the endpoint then refreshing |
| Modify | `Cue/Paywall/CuePaywall.swift` — "Try Super free for a day" button under the RC footer |
| Modify | `Cue/Search/PlayableMenuView.swift` — offer the day pass from `offerSuperForDownloads()` |
| Modify | `Cue/Preferences/PreferenceScreen.swift` — "Super Day · ends in …" on the Cue Super row |
| Modify | `Packages/Analytics/.../Events.swift` — `superDayStarted`, `superDayConverted` |
| Create | Worker handler for `POST /super-day` (backend repo) |
