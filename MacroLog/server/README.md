# MacroLog Claude proxy

A tiny Cloudflare Worker that lets friends & family use MacroLog **without
their own Anthropic account**. Your Claude API key lives here as a secret; the
app sends requests with a per-person **invite code** instead of a key. The
proxy forwards to Anthropic, meters each person's tokens, and computes their
monthly **cost in dollars** — so if you later decide to charge, you'll know
exactly what each user costs. A per-person monthly spend cap (default $10)
protects your bill.

Free tier is plenty: Workers gives 100k requests/day; a heavy tracker logs
maybe 30 meals a day.

## One-time setup (~10 minutes, from your Mac's Terminal)

1. **Create a free Cloudflare account** at dash.cloudflare.com (no domain needed).

2. **Install and log in to Wrangler** (Cloudflare's CLI):

   ```bash
   npm install -g wrangler
   wrangler login
   ```

3. **Create the storage namespace** (holds invite codes + usage):

   ```bash
   cd /Users/alexnovak/Personal-Apps/MacroLog/server
   wrangler kv namespace create USERS
   ```

   It prints an `id = "…"` line — paste that id into `wrangler.toml` where it
   says `PASTE_KV_NAMESPACE_ID_HERE`.

3b. **Create the community food database** (shared foods & recipes — every
   user's label scans and CSV uploads sync here and improve matching for
   everyone):

   ```bash
   wrangler d1 create macrolog-foods
   ```

   It prints a `database_id = "…"` line — paste that id into `wrangler.toml`
   where it says `PASTE_D1_DATABASE_ID_HERE`. Tables are created
   automatically on first use.

4. **Set the two secrets** (paste the value when each command prompts):

   ```bash
   wrangler secret put ANTHROPIC_API_KEY   # your sk-ant-… key
   wrangler secret put ADMIN_TOKEN         # invent a long random password
   ```

5. **Deploy:**

   ```bash
   wrangler deploy
   ```

   It prints your Worker URL, like `https://macrolog-proxy.<your-subdomain>.workers.dev`.
   **That URL goes into the app** — set it as `ClaudeEndpoint.defaultProxyURL`
   in `MacroLog/Services/ClaudeEndpoint.swift` before building for TestFlight
   (then friends only ever type their invite code).

## Managing people

Invite codes are anything 4–40 letters/digits/dashes — e.g. `MOM-7291`.
Replace `$TOKEN` with your ADMIN_TOKEN and the URL with your Worker URL.

```bash
# Add a person
curl -X POST https://macrolog-proxy.YOURNAME.workers.dev/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "MOM-7291", "name": "Mom"}'

# Remove a person (stops their access immediately)
curl -X DELETE https://macrolog-proxy.YOURNAME.workers.dev/admin/users/MOM-7291 \
  -H "Authorization: Bearer $TOKEN"

# List everyone
curl https://macrolog-proxy.YOURNAME.workers.dev/admin/users \
  -H "Authorization: Bearer $TOKEN"
```

## Reading the usage report

```bash
# This month, as JSON
curl https://macrolog-proxy.YOURNAME.workers.dev/admin/usage \
  -H "Authorization: Bearer $TOKEN"

# A specific month
curl "https://macrolog-proxy.YOURNAME.workers.dev/admin/usage?month=2026-06" \
  -H "Authorization: Bearer $TOKEN"
```

For a readable table in the browser, open
`…/admin/usage?html=1` — but since browsers can't send the auth header, use
this from Terminal instead and it opens in your browser:

```bash
curl -s "https://macrolog-proxy.YOURNAME.workers.dev/admin/usage?html=1" \
  -H "Authorization: Bearer $TOKEN" > /tmp/usage.html && open /tmp/usage.html
```

Report columns: requests, tokens in/out, and **estimated cost per person** —
computed from the model's public per-token pricing (see `PRICES` in
`worker.js`; update it if the app changes models or Anthropic changes prices).

## Suggestions board moderation

The in-app suggestions board (Settings → Community suggestions) stores its
entries in the same D1 database. Remove one (votes and comments included):

```bash
curl -X DELETE https://macrolog-proxy.YOURNAME.workers.dev/admin/suggestions/ID \
  -H "Authorization: Bearer $TOKEN"
```

(The ID is visible in the `/suggestions` response, or ask the reporter.)

## Knobs

- **Per-person monthly cap:** `MONTHLY_COST_CAP_USD` in `wrangler.toml`
  (default `"10"`). Past the cap that code gets HTTP 429 until the month rolls
  over; the app shows it as an error message.
- **Cutting someone off:** delete their user (above) — takes effect on their
  next request.
