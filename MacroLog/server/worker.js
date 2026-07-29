/**
 * MacroLog Claude proxy — a tiny Cloudflare Worker that lets friends & family
 * use the app without their own Anthropic account.
 *
 * What it does:
 *  - Holds YOUR Anthropic API key as a Worker secret (never in the app).
 *  - Authenticates each request with a per-person invite code
 *    (`x-macrolog-user` header) you hand out.
 *  - Forwards the request body to Anthropic's Messages API unchanged.
 *  - Meters usage per person per month (requests, input/output tokens, and
 *    estimated cost) into Workers KV, and exposes an admin usage report —
 *    so you know exactly what each person costs before deciding pricing.
 *  - Enforces a per-person monthly cost cap so a runaway phone can't surprise
 *    you on the bill.
 *
 * See server/README.md for setup (about 10 minutes, free tier).
 */

// $ per million tokens, by model prefix (first match wins). Update as pricing
// or the app's model choice changes.
const PRICES = [
  { prefix: "claude-opus", inPerM: 15, outPerM: 75 },
  { prefix: "claude-sonnet", inPerM: 3, outPerM: 15 },
  { prefix: "claude-haiku", inPerM: 1, outPerM: 5 },
];
const DEFAULT_PRICE = { inPerM: 3, outPerM: 15 };

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/messages" && request.method === "POST") {
        return await proxyMessages(request, env);
      }
      if (url.pathname === "/foods" || url.pathname === "/recipes" ||
          url.pathname === "/recipes/search") {
        return await handleDatabase(request, env, url);
      }
      if (url.pathname.startsWith("/admin/")) {
        return await handleAdmin(request, env, url);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: `proxy error: ${err.message}` }, 500);
    }
  },
};

// MARK: Community database (D1)
// The shared food + recipe database every app install syncs with: scans and
// CSV imports push up, everyone pulls each other's contributions down.
// Auth: the same per-person invite code as the Claude proxy.

let tablesReady = false;
async function ensureTables(env) {
  if (tablesReady) return;
  await env.FOODDB.exec(
    "CREATE TABLE IF NOT EXISTS foods (name_key TEXT PRIMARY KEY, name TEXT, brand TEXT, serving TEXT, calories REAL, protein REAL, carbs REAL, fat REAL, micros TEXT, source TEXT, created_at INTEGER)"
  );
  await env.FOODDB.exec(
    "CREATE TABLE IF NOT EXISTS recipes (name_key TEXT PRIMARY KEY, name TEXT, slot TEXT, instructions TEXT, ingredients TEXT, created_at INTEGER)"
  );
  tablesReady = true;
}

// Mirrors the app's CustomFoodStore.nameKey EXACTLY (letter-only tokens,
// deduped and sorted) — the two must agree or the same product can land
// twice across devices.
function nameKey(...parts) {
  const tokens = parts
    .join(" ")
    .toLowerCase()
    .replace(/[^a-z]+/g, " ")
    .split(/\s+/)
    .filter(Boolean);
  return [...new Set(tokens)].sort().join(" ");
}

async function requireUser(request, env) {
  const code = (request.headers.get("x-macrolog-user") || "").trim();
  if (!code) return null;
  const raw = await env.USERS.get(`user:${code}`);
  return raw ? code : null;
}

async function handleDatabase(request, env, url) {
  if (!env.FOODDB) {
    return json({ error: "food database not configured (add the D1 binding — see server/README.md)" }, 503);
  }
  const user = await requireUser(request, env);
  if (!user) return json({ error: "invalid invite code" }, 403);
  await ensureTables(env);

  // POST /foods {items: [...]} — contribute rows; duplicates are ignored.
  if (url.pathname === "/foods" && request.method === "POST") {
    const { items } = await request.json();
    if (!Array.isArray(items) || items.length > 500) {
      return json({ error: "items must be an array of at most 500" }, 400);
    }
    let added = 0;
    for (const f of items) {
      if (!f?.name || typeof f.calories !== "number") continue;
      const result = await env.FOODDB
        .prepare(
          "INSERT OR IGNORE INTO foods (name_key, name, brand, serving, calories, protein, carbs, fat, micros, source, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(
          nameKey(f.name, f.brand || ""),
          String(f.name).slice(0, 200),
          String(f.brand || "").slice(0, 100),
          String(f.serving || "1 serving").slice(0, 100),
          f.calories, f.protein || 0, f.carbs || 0, f.fat || 0,
          f.micros ? String(f.micros).slice(0, 4000) : null,
          String(f.source || "scan").slice(0, 20),
          Date.now()
        )
        .run();
      if (result.meta.changes > 0) added += 1;
    }
    return json({ ok: true, added });
  }

  // GET /foods?since=<ms> — pull rows added after the cursor.
  if (url.pathname === "/foods" && request.method === "GET") {
    const since = Number(url.searchParams.get("since") || "0");
    const { results } = await env.FOODDB
      .prepare("SELECT * FROM foods WHERE created_at > ? ORDER BY created_at LIMIT 500")
      .bind(since)
      .all();
    const next = results.length
      ? results[results.length - 1].created_at
      : since;
    return json({ items: results, next });
  }

  // POST /recipes — share one recipe; duplicates (by name) are ignored.
  if (url.pathname === "/recipes" && request.method === "POST") {
    const r = await request.json();
    if (!r?.name) return json({ error: "name required" }, 400);
    const result = await env.FOODDB
      .prepare(
        "INSERT OR IGNORE INTO recipes (name_key, name, slot, instructions, ingredients, created_at) VALUES (?,?,?,?,?,?)"
      )
      .bind(
        nameKey(r.name),
        String(r.name).slice(0, 200),
        String(r.slot || "any").slice(0, 20),
        String(r.instructions || "").slice(0, 8000),
        String(r.ingredients || "[]").slice(0, 16000),
        Date.now()
      )
      .run();
    return json({ ok: true, added: result.meta.changes > 0 });
  }

  // GET /recipes/search?q= — for the app's recipe search "Community" source.
  if (url.pathname === "/recipes/search" && request.method === "GET") {
    const q = (url.searchParams.get("q") || "").trim().toLowerCase();
    if (!q) return json({ items: [] });
    const { results } = await env.FOODDB
      .prepare("SELECT name, slot, instructions, ingredients FROM recipes WHERE name_key LIKE ? LIMIT 20")
      .bind(`%${q.replace(/[%_]/g, "")}%`)
      .all();
    return json({ items: results });
  }

  return json({ error: "not found" }, 404);
}

// MARK: Proxy

async function proxyMessages(request, env) {
  const code = (request.headers.get("x-macrolog-user") || "").trim();
  if (!code) return json({ error: "missing invite code" }, 401);

  const userRaw = await env.USERS.get(`user:${code}`);
  if (!userRaw) return json({ error: "unknown invite code" }, 403);
  const user = JSON.parse(userRaw);

  // Monthly cost cap (micro-dollars) — default $10/person/month.
  const capMicros = Number(env.MONTHLY_COST_CAP_USD || "10") * 1_000_000;
  const month = currentMonth();
  const usageKey = `usage:${code}:${month}`;
  const existing = await readUsage(env, usageKey);
  if (existing.costMicros >= capMicros) {
    return json(
      { error: "monthly usage limit reached for this invite code" },
      429
    );
  }

  // Forward the body untouched; the app already speaks Anthropic's wire format.
  const body = await request.text();
  const upstream = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version":
        request.headers.get("anthropic-version") || "2023-06-01",
    },
    body,
  });

  const responseText = await upstream.text();

  // Meter successful calls: Anthropic returns usage.{input,output}_tokens.
  if (upstream.ok) {
    try {
      const parsed = JSON.parse(responseText);
      const inTok = parsed?.usage?.input_tokens || 0;
      const outTok = parsed?.usage?.output_tokens || 0;
      const price = priceFor(parsed?.model || JSON.parse(body)?.model || "");
      const costMicros = Math.round(
        (inTok * price.inPerM + outTok * price.outPerM)
      );
      // (tokens × $/MTok) === micro-dollars, since M cancels: neat and integer.
      existing.requests += 1;
      existing.inputTokens += inTok;
      existing.outputTokens += outTok;
      existing.costMicros += costMicros;
      existing.name = user.name || code;
      await env.USERS.put(usageKey, JSON.stringify(existing));
    } catch {
      // Metering must never break the actual response.
    }
  }

  return new Response(responseText, {
    status: upstream.status,
    headers: { "content-type": "application/json" },
  });
}

function priceFor(model) {
  for (const p of PRICES) if (model.startsWith(p.prefix)) return p;
  return DEFAULT_PRICE;
}

async function readUsage(env, key) {
  const raw = await env.USERS.get(key);
  if (raw) return JSON.parse(raw);
  return { requests: 0, inputTokens: 0, outputTokens: 0, costMicros: 0, name: "" };
}

// MARK: Admin
// All admin calls need `Authorization: Bearer <ADMIN_TOKEN>`.
//   POST   /admin/users            {"code": "ALEX-MOM", "name": "Mom"}
//   DELETE /admin/users/CODE
//   GET    /admin/users
//   GET    /admin/usage[?month=YYYY-MM][&html=1]

async function handleAdmin(request, env, url) {
  const auth = request.headers.get("authorization") || "";
  if (auth !== `Bearer ${env.ADMIN_TOKEN}`) {
    return json({ error: "unauthorized" }, 401);
  }

  if (url.pathname === "/admin/users" && request.method === "POST") {
    const { code, name } = await request.json();
    if (!code || !/^[A-Za-z0-9_-]{4,40}$/.test(code)) {
      return json({ error: "code must be 4-40 letters/digits/dashes" }, 400);
    }
    await env.USERS.put(`user:${code}`, JSON.stringify({ name: name || code }));
    return json({ ok: true, code, name: name || code });
  }

  const deleteMatch = url.pathname.match(/^\/admin\/users\/([A-Za-z0-9_-]+)$/);
  if (deleteMatch && request.method === "DELETE") {
    await env.USERS.delete(`user:${deleteMatch[1]}`);
    return json({ ok: true, deleted: deleteMatch[1] });
  }

  if (url.pathname === "/admin/users" && request.method === "GET") {
    const list = await env.USERS.list({ prefix: "user:" });
    const users = [];
    for (const k of list.keys) {
      const raw = await env.USERS.get(k.name);
      users.push({ code: k.name.slice(5), ...(raw ? JSON.parse(raw) : {}) });
    }
    return json({ users });
  }

  if (url.pathname === "/admin/usage" && request.method === "GET") {
    const month = url.searchParams.get("month") || currentMonth();
    const list = await env.USERS.list({ prefix: "usage:" });
    const rows = [];
    for (const k of list.keys) {
      // usage:<code>:<YYYY-MM>
      const parts = k.name.split(":");
      if (parts[2] !== month) continue;
      const usage = await readUsage(env, k.name);
      rows.push({
        code: parts[1],
        name: usage.name || parts[1],
        requests: usage.requests,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        costUSD: +(usage.costMicros / 1_000_000).toFixed(4),
      });
    }
    rows.sort((a, b) => b.costUSD - a.costUSD);
    const total = +rows.reduce((s, r) => s + r.costUSD, 0).toFixed(4);

    if (url.searchParams.get("html")) {
      return htmlUsage(month, rows, total);
    }
    return json({ month, totalUSD: total, users: rows });
  }

  return json({ error: "not found" }, 404);
}

function htmlUsage(month, rows, total) {
  const tr = rows
    .map(
      (r) =>
        `<tr><td>${escapeHTML(r.name)}</td><td>${escapeHTML(r.code)}</td><td>${r.requests}</td><td>${r.inputTokens.toLocaleString()}</td><td>${r.outputTokens.toLocaleString()}</td><td>$${r.costUSD.toFixed(2)}</td></tr>`
    )
    .join("");
  const html = `<!doctype html><meta charset="utf-8"><title>MacroLog usage ${month}</title>
<style>body{font-family:-apple-system,sans-serif;margin:2rem}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.4rem .8rem;text-align:right}th:first-child,td:first-child,th:nth-child(2),td:nth-child(2){text-align:left}</style>
<h2>MacroLog usage — ${month}</h2>
<table><tr><th>Name</th><th>Code</th><th>Requests</th><th>Tokens in</th><th>Tokens out</th><th>Cost</th></tr>${tr}</table>
<p><strong>Total: $${total.toFixed(2)}</strong></p>`;
  return new Response(html, { headers: { "content-type": "text/html" } });
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function currentMonth() {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
