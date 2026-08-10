# iCloud sync (SwiftData + CloudKit private database)

Foob's diary, custom food database, remembered matches, and recipes sync
silently across a person's own devices via their private iCloud account.
This doc is written to be copied wholesale into the next app in the fleet —
it's the recipe, not a changelog of what Foob specifically did.

## Why CloudKit private database, not Sign in with Apple

Sync needs *some* identity to key data on. Two ways to get one:

- **Sign in with Apple / any account system** — needs a server to hold
  accounts, a sign-in screen, session tokens, and a database you operate and
  are responsible for securing.
- **The device's iCloud account** — already signed in on every iPhone.
  SwiftData's CloudKit integration uses it directly: no server, no sign-in
  screen, no account system to build or breach. The identity is "whichever
  Apple ID this iPhone is signed into," which is exactly the identity iCloud
  Backup and every other stock Apple sync feature uses.

For a single-user-per-account app like a food diary, that's the entire
requirement. There's nothing to gain from a server-side account system, and
a lot to avoid: no auth code, no password resets, no breach surface, no
hosting bill for the data itself. Sign in with Apple only starts to earn its
keep when the app needs cross-account sharing, a web/Android counterpart, or
server-side logic that has to run even when the device is offline — none of
which applies here.

The trade-off: sync is scoped to "this person's own devices, tied to their
Apple ID." No cross-platform sync, no sharing between people. Fine for a
food diary; wouldn't be fine for something collaborative.

## The container ID convention

`iCloud.<bundle id>` — for Foob, `iCloud.com.alexnovak.Foob` matching bundle
ID `com.alexnovak.Foob`. Keep this pattern for every app in the fleet: it's
predictable, it's what Xcode generates automatically when you check the
iCloud capability, and it means the container ID never needs to be looked up
separately from the bundle ID.

The ID appears in exactly two places and they must match:
`Foob.entitlements` (`com.apple.developer.icloud-container-identifiers`) and
`AppModelContainer.cloudKitContainerID` in code (used both to open the store
and by `CloudSyncStatus` to query `CKContainer.accountStatus()`).

## The CloudKit model rules

`NSPersistentCloudKitContainer` (which SwiftData's `cloudKitDatabase` option
sits on top of) imposes real constraints on the model, because CloudKit
records don't support everything Core Data / SwiftData normally allow. Get
these wrong and the container either refuses to open or silently drops the
CloudKit path (SwiftData throws on `ModelContainer` init, caught by
`AppModelContainer`'s fallback below):

1. **Every attribute must be optional or have a default value.** CloudKit
   records are added to over time, and a field with no default has no valid
   value the first time an old record syncs in without it. Every
   non-optional stored property across `Meal`, `FoodItem`, `Recipe`,
   `RecipeIngredient`, `CustomFood`, and `RememberedMatch` either got a
   default (`= .now`, `= ""`, `= 0`) or was made `Optional`.

2. **Every to-many relationship must be optional.** `Meal.items` is
   `[FoodItem]?`, `Recipe.ingredients` is `[RecipeIngredient]?`. A
   non-optional array relationship isn't representable as a CloudKit
   reference set.

3. **No unique constraints.** `@Attribute(.unique)` is unsupported —
   CloudKit's eventual-consistency model can't enforce uniqueness across
   devices that synced at different times. Every `@Attribute(.unique)` in
   the schema had to come out. This pushes de-duplication into application
   code, at write time, instead of the database enforcing it:

   - `CustomFoodStore.addIfNew` computes a normalized `nameKey` (from
     `NameTokens.tokens(name)` unioned with tokens of the brand) and fetches
     by that key before inserting, so the same scanned label never produces
     two rows even if it's scanned on two devices before they've synced.
   - `RememberedMatchStore.remember` does the same thing as an upsert:
     fetch by the normalized phrase, update the existing row if found
     (and delete any stray duplicates that arrived from another device),
     insert only if nothing matched.

   The pattern generalizes: anywhere a field used to be `.unique`, replace
   it with a fetch-then-insert-or-update helper keyed on that field, called
   from every write path instead of trusting the database to reject
   duplicates.

## Optional-stored / non-optional-computed accessor pattern

Rule 2 above (optional relationships) would otherwise leak `?? []`
unwrapping into every call site that reads `meal.items` or
`recipe.ingredients`. Instead, the stored property stays private-ish and
optional to satisfy CloudKit, and a computed property gives the rest of the
app a non-optional view:

```swift
@Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
var items: [FoodItem]?

/// Non-optional view of `items`. CloudKit forces the stored relationship to
/// be optional; nothing outside this file should have to care.
var itemList: [FoodItem] { items ?? [] }
```

Every other file reads `meal.itemList`, never `meal.items`. Same shape for
`Recipe.ingredients` / `Recipe.ingredientList`. Apply this pattern to any
relationship CloudKit forces optional: keep the CloudKit-mandated
optionality contained to the model file, expose an `X ?? []` (or `?? ""` /
`?? 0` for scalars) computed property with a name that reads naturally, and
never let `nil`-checking spread into views or services.

## Entitlements and project.yml

Four things have to be present together or the CloudKit path fails silently
(falls back to local-only — see below):

- **iCloud capability, CloudKit service** — `Foob.entitlements`:
  `com.apple.developer.icloud-services` = `["CloudKit"]`.
- **Container identifier** — same file:
  `com.apple.developer.icloud-container-identifiers` = `["iCloud.<bundle id>"]`,
  matching the ID in code.
- **Push entitlement** — `aps-environment` = `development` (or
  `production` for release builds). CloudKit sync uses silent push
  notifications to tell other devices data changed; without this entitlement
  those notifications can't be delivered and sync becomes pull-only (next
  app launch or manual foreground) instead of near-immediate.
- **Background mode** — `project.yml`, under the app target's `Info.plist`
  block:

  ```yaml
  UIBackgroundModes:
    - remote-notification
  ```

  This lets the app wake on the silent push CloudKit sends so sync happens
  promptly instead of only on next launch.

## Local-first / graceful degradation

Sync must never be a precondition for the app working. `AppModelContainer`
tries to open the shared `ModelContainer` with the CloudKit configuration
first; if that throws for *any* reason (no entitlement, simulator without
iCloud support, a schema CloudKit rejects), it falls back to the exact same
on-disk store with `cloudKitDatabase: .none` and continues — nothing is
lost, sync is just off until whatever broke is fixed. This is a `StoreMode`
enum (`.cloudKit` / `.localOnly(reason:)`) the app can inspect but never
gates on.

Separately, a CloudKit-backed store can open fine while the *device* isn't
signed into iCloud, has iCloud Drive off for the app, or has no network —
those are all supported, permanent-or-temporary states, not errors. That
half is `CloudSyncStatus`, which asks `CKContainer.accountStatus()` and
reports a plain-language reason (`.on` / `.off(reason:)` / `.unknown`) for
the one status row in Settings. Nothing else in the app reads it — there's
no sync-required screen, no blocking spinner, no "sign in to continue."

## Verifying it actually works

This cannot be checked in the Simulator — CloudKit sync needs a real
account signed into a real device. The check:

1. Build and run a **signed build on a real iPhone**, signed into the
   **owner's actual Apple ID** (a Simulator or a development-only build
   without the entitlements applied won't exercise the CloudKit path at
   all — `AppModelContainer` will silently be on the local-only fallback).
2. Log some meals, confirm they appear in the diary.
3. Give sync a few seconds to actually push (or check Settings → iCloud
   sync shows "On").
4. **Delete the app** from the device.
5. **Reinstall** it (same Apple ID still signed in under Settings → \[name\]
   → iCloud).
6. Open the app: the previously logged data should be back, pulled down
   from the private CloudKit database rather than reconstructed locally.

If step 6 comes back empty, check in order: Settings → iCloud sync row for
the actual state/reason, that the container ID in `Foob.entitlements`
matches `AppModelContainer.cloudKitContainerID` exactly, and the device
console (`os.Logger` subsystem `com.alexnovak.foob`, category `cloudkit`)
for the store-open and account-status log lines.
