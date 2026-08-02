# Getting Foob to friends & family (TestFlight)

The path from "runs on my phone for 7 days" to "anyone I invite can install
it" is Apple's **TestFlight**. This is the complete checklist, in order.

## Why TestFlight (and why the app kept expiring)

Building from Xcode with a free Apple ID signs the app for **7 days** — after
that it stops launching until you rebuild. The **Apple Developer Program**
($99/year) removes that limit for your own device (1-year signing) and
unlocks TestFlight: friends install the free TestFlight app, tap your invite
link, and get Foob over the air. Builds last 90 days each; pushing an
update resets the clock and updates everyone automatically.

## Step 0 — Deploy the proxy first

Friends don't have Anthropic accounts. Deploy the usage-metering proxy
(`server/README.md`, ~10 minutes) and then bake its URL into the app:

1. Open `Foob/Services/ClaudeEndpoint.swift`
2. Set `defaultProxyURL` to your Worker URL, e.g.
   `static let defaultProxyURL = "https://macrolog-proxy.YOURNAME.workers.dev"`

Now each friend's entire setup is typing the invite code you text them.

## Step 1 — Enroll (one time)

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll)
   and enroll as an **individual** with your Apple ID ($99/year).
   Approval is usually within 48 hours.
2. In Xcode → Settings → Accounts, make sure that Apple ID is signed in.
3. Put your **Team ID** (the 10-character code at developer.apple.com →
   Membership) into `Foob/Signing.xcconfig`:

       DEVELOPMENT_TEAM = ABCDE12345

   Do this rather than only picking the team in Xcode's Signing &
   Capabilities tab — `xcodegen generate` rewrites the `.xcodeproj` and would
   drop the choice, so you'd re-pick it after every project regeneration. The
   xcconfig applies to both the app and the widget extension.

## Step 2 — App record (one time)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   **My Apps** → **+** → **New App**.
2. Platform iOS; Name **Foob** (or a variant if taken); Primary language;
   **Bundle ID**: `com.alexnovak.Foob` (must match the project);
   SKU: anything, e.g. `foob-001`.

## Step 3 — Privacy policy URL (already hosted)

External TestFlight needs a privacy policy **URL**. The proxy server hosts
it: once the Worker is deployed (`server/README.md`), the policy is live at

    https://<your-worker>.workers.dev/privacy

Use that URL wherever App Store Connect asks for a privacy policy (the
TestFlight test information, and later App Privacy). The page's source of
truth is `PRIVACY_HTML` in `server/worker.js`, mirrored by
`docs/privacy-policy.md` — edit both together and redeploy.

## Step 3b — App Privacy questionnaire

App Store Connect → Foob → **App Privacy**. Required before external
TestFlight, and it must match what the server actually stores.

The diary never leaves the device, and meal text/photos sent to Claude are
transient. But the proxy *does* retain things, so "Data Not Collected" is
not an honest answer while the community features are on.

These are the five entries to declare — the answers submitted for 1.0:

| Data type | Section | Linked to identity | Tracking | Purpose |
|---|---|---|---|---|
| User ID | Identifiers | Yes | No | App Functionality |
| Product Interaction | Usage Data | Yes | No | Analytics |
| Other User Content | User Content | Yes | No | App Functionality |
| Crash Data | Diagnostics | No | No | App Functionality |
| Performance Data | Diagnostics | No | No | App Functionality |

- **User ID** is the invite code; **Product Interaction** is the per-code
  request and token counts that drive the cost report; **Other User Content**
  is suggestions and comments posted with a display name.
- **Crash and Performance Data** are true the moment you're on TestFlight —
  Xcode Organizer shows you crash and hang reports from testers. Not linked
  to identity, because Apple aggregates them before you see them.
- **Tracking: No** on all five. Nothing is linked to third-party data or ads.

Three things that are *not* collected and must not be declared: the food
diary (never transmitted), shared food-database rows (published nutrition
facts off labels and uploaded sheets — not personal data, and meals you log
are never contributed; see `CommunitySync.shareableSources`), and photos or
audio (analyzed in-flight, never stored server-side).

If you turn the suggestions board off for a round, User Content drops off
this table.

**This declaration must be updated before — not after — shipping a build
that collects something new.** Editing it is free and takes a minute, so
there's no reason to pre-declare things the app doesn't do yet. If media
storage or contact details (name/phone/email at signup) ever land, they get
added here in the same change that adds the feature.

## Step 4 — Archive & upload (every release)

In Xcode with the Foob project open:

1. Select the **Foob** scheme and destination **Any iOS Device (arm64)**.
2. Bump the build number (project.yml `CURRENT_PROJECT_VERSION`, then
   `xcodegen generate`) — every upload needs a higher build number.
3. **Product → Archive**.
4. When the Organizer opens: **Distribute App → TestFlight & App Store →
   Upload**, accept the signing defaults.
5. Wait ~10–30 minutes for processing (email arrives when done).

**Export compliance** — nothing to do. US export rules make Apple ask every
app whether it uses encryption; plain HTTPS to your own server is exempt.
`project.yml` already sets `ITSAppUsesNonExemptEncryption: false`, which
answers it in the build so App Store Connect stops prompting. If it ever
asks anyway, the build predates that line — answer **No** and it goes away
next upload.

## Step 5 — Invite people

In App Store Connect → Foob → **TestFlight** tab:

- **Internal testing** (up to 100 people who you add by Apple ID email):
  create a group, add the build, add testers. No review needed — fastest.
- **External testing** (up to 10,000, invite by link): create a group, add
  the build, fill in the "What to test" note; the **first** external build
  goes through a light Beta App Review (usually < 1 day). Then share the
  **public link** — anyone who taps it installs the app.

For family: external with the public link is the least admin work. Internal
testing is instant and review-free, but every tester needs an account on
your App Store Connect team — fine for you, awkward for relatives.

### Filling in the review forms

Three fields live in different places, which is the confusing part:

- **Beta App Description** and **Feedback Email** — TestFlight → **Test
  Information** (applies to all builds).
- **What to Test** — *not* in Test Information. It's on the individual
  build: TestFlight → **Builds → iOS → click the build number**. It won't
  appear until processing finishes.
- **Sign-in required** — App Review Information, on the external group.

**The sign-in fields are the most common rejection.** Foob has no accounts,
but a reviewer who can't get past onboarding rejects the build, so declaring
"no sign-in required" is the riskier answer. Leave the toggle **on**, put a
working invite code in *both* the username and password fields (the form
requires both), and explain in the notes:

> This app has no user accounts, passwords, or email sign-up. Access is
> granted by a single invite code.
>
> On the onboarding screen, tap "Use an invite code" and enter: REVIEW-2026
>
> The username and password fields above both contain that same invite code,
> because the App Store Connect form requires both — there is no separate
> password.

Create the code **before submitting**, and enter it in the app yourself to
confirm it works. A code that 403s is the same rejection as no code at all.

```bash
curl -X POST https://macrolog-proxy.YOURNAME.workers.dev/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "REVIEW-2026", "name": "App Review"}'
```

Once review passes, delete it so it isn't a live code sitting on the server:

```bash
curl -X DELETE https://macrolog-proxy.YOURNAME.workers.dev/admin/users/REVIEW-2026 \
  -H "Authorization: Bearer $TOKEN"
```

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

### `{"error":"unauthorized"}`

`worker.js` compares the header against `Bearer ${env.ADMIN_TOKEN}` with
exact string equality, so a missing token, a stray space, and a completely
wrong token all fail identically. In rough order of likelihood:

1. **`$TOKEN` isn't set in this terminal.** `export` only lasts for one
   window, so a new tab needs it again. Check the length without printing
   the secret — `0` means it's unset:

       printf '%s' "$TOKEN" | wc -c

   If it's one or two *more* than the real token, you've copy-pasted a
   trailing newline or space. Re-export with quotes: `export TOKEN='…'`

2. **The secret was never set on the Worker.** `ADMIN_TOKEN` is a secret,
   not a `[vars]` entry, so if it's missing `env.ADMIN_TOKEN` is `undefined`
   and the Worker is literally comparing against `"Bearer undefined"`. Test
   for exactly that:

       curl -s https://macrolog-proxy.YOURNAME.workers.dev/admin/users \
         -H "Authorization: Bearer undefined"

   A user list back confirms it. Fix with `wrangler secret put ADMIN_TOKEN`
   from `server/`, then verify with `wrangler secret list`.

Set `ADMIN_TOKEN` to something random rather than a memorable word —
`openssl rand -hex 32`. It is the only thing between the public internet and
the ability to add users, delete accounts, and read everyone's usage.

## Updating everyone later

Push new code → bump build number → Archive → Upload → add the build to the
same TestFlight group. Testers get it automatically (TestFlight notifies
them). Builds expire after 90 days, so ship at least quarterly.

## When you outgrow TestFlight

The same app record, archive, and privacy setup feeds a real **App Store**
release — you'd add screenshots, a description, and submit for full review.
The usage report tells you what each user costs before you price anything.

The reason to bother, for a family app nobody intends to sell: TestFlight
builds expire every 90 days, so staying on it means re-uploading four times
a year forever or everyone's app stops opening. An App Store release
installs once and updates itself. Being publicly listed matters less than it
sounds — without an invite code a stranger who downloads it can't do
anything — and [unlisted app distribution][unlisted] keeps it out of search
entirely, reachable only by direct link.

[unlisted]: https://developer.apple.com/support/unlisted-app-distribution/
