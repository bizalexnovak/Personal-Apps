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
      if (url.pathname.startsWith("/admin/")) {
        return await handleAdmin(request, env, url);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: `proxy error: ${err.message}` }, 500);
    }
  },
};

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
