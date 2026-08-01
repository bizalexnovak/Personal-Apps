# Getting MacroLog to friends & family (TestFlight)

The path from "runs on my phone for 7 days" to "anyone I invite can install
it" is Apple's **TestFlight**. This is the complete checklist, in order.

## Why TestFlight (and why the app kept expiring)

Building from Xcode with a free Apple ID signs the app for **7 days** — after
that it stops launching until you rebuild. The **Apple Developer Program**
($99/year) removes that limit for your own device (1-year signing) and
unlocks TestFlight: friends install the free TestFlight app, tap your invite
link, and get MacroLog over the air. Builds last 90 days each; pushing an
update resets the clock and updates everyone automatically.

## Step 0 — Deploy the proxy first

Friends don't have Anthropic accounts. Deploy the usage-metering proxy
(`server/README.md`, ~10 minutes) and then bake its URL into the app:

1. Open `MacroLog/Services/ClaudeEndpoint.swift`
2. Set `defaultProxyURL` to your Worker URL, e.g.
   `static let defaultProxyURL = "https://macrolog-proxy.YOURNAME.workers.dev"`

Now each friend's entire setup is typing the invite code you text them.

## Step 1 — Enroll (one time)

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll)
   and enroll as an **individual** with your Apple ID ($99/year).
   Approval is usually within 48 hours.
2. In Xcode → Settings → Accounts, make sure that Apple ID is signed in.
3. Put your **Team ID** (the 10-character code at developer.apple.com →
   Membership) into `MacroLog/Signing.xcconfig`:

       DEVELOPMENT_TEAM = ABCDE12345

   Do this rather than only picking the team in Xcode's Signing &
   Capabilities tab — `xcodegen generate` rewrites the `.xcodeproj` and would
   drop the choice, so you'd re-pick it after every project regeneration. The
   xcconfig applies to both the app and the widget extension.

## Step 2 — App record (one time)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   **My Apps** → **+** → **New App**.
2. Platform iOS; Name **MacroLog** (or a variant if taken); Primary language;
   **Bundle ID**: `com.alexnovak.MacroLog` (must match the project);
   SKU: anything, e.g. `macrolog-001`.

## Step 3 — Privacy policy URL (already hosted)

External TestFlight needs a privacy policy **URL**. The proxy server hosts
it: once the Worker is deployed (`server/README.md`), the policy is live at

    https://<your-worker>.workers.dev/privacy

Use that URL wherever App Store Connect asks for a privacy policy (the
TestFlight test information, and later App Privacy). The page's source of
truth is `PRIVACY_HTML` in `server/worker.js`, mirrored by
`docs/privacy-policy.md` — edit both together and redeploy.

For the **App Privacy questionnaire**, MacroLog's honest answers:
- Data collected: **None** collected by you from users (diary data never
  leaves the device; meal text/photos are processed per-request and not
  retained; invite-code metering stores counts, not content).
- Tracking: **No**.

## Step 4 — Archive & upload (every release)

In Xcode with the MacroLog project open:

1. Select the **MacroLog** scheme and destination **Any iOS Device (arm64)**.
2. Bump the build number (project.yml `CURRENT_PROJECT_VERSION`, then
   `xcodegen generate`) — every upload needs a higher build number.
3. **Product → Archive**.
4. When the Organizer opens: **Distribute App → TestFlight & App Store →
   Upload**, accept the signing defaults.
5. Wait ~10–30 minutes for processing (email arrives when done).

## Step 5 — Invite people

In App Store Connect → MacroLog → **TestFlight** tab:

- **Internal testing** (up to 100 people who you add by Apple ID email):
  create a group, add the build, add testers. No review needed — fastest.
- **External testing** (up to 10,000, invite by link): create a group, add
  the build, fill in the "What to test" note; the **first** external build
  goes through a light Beta App Review (usually < 1 day). Then share the
  **public link** — anyone who taps it installs the app.

For family: external with the public link is the least admin work.

## Step 6 — Per-person invite codes

For each person, create a proxy invite code and text it to them with the
TestFlight link:

```bash
curl -X POST https://macrolog-proxy.YOURNAME.workers.dev/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "MOM-7291", "name": "Mom"}'
```

They install → open → pick **Invite code** → type it → done. Check what
everyone's usage costs any time with the `/admin/usage` report
(`server/README.md`).

## Updating everyone later

Push new code → bump build number → Archive → Upload → add the build to the
same TestFlight group. Testers get it automatically (TestFlight notifies
them). Builds expire after 90 days, so ship at least quarterly.

## When you outgrow TestFlight

The same app record, archive, and privacy setup feeds a real **App Store**
release — you'd add screenshots, a description, and submit for full review.
The usage report tells you what each user costs before you price anything.
