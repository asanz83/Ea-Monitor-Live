// Worker de ea-monitor-live: recibe datos en vivo del EA reportero (POST /ingest)
// y los sirve al panel (GET /api/*). El panel estático se sirve solo (ASSETS
// binding, ver wrangler.toml) para cualquier ruta que no empiece por /api o
// /ingest. La autenticación del panel para personas la hace Cloudflare Access
// por delante de todo salvo /ingest (se configura en el dashboard, no aquí) —
// /ingest se protege aquí con el token por cuenta.

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function handleIngest(request, env) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return json({ error: true, message: "Falta token" }, 401);

  const tokenHash = await sha256Hex(token);
  const account = await env.DB
    .prepare("SELECT id FROM accounts WHERE token_hash = ?")
    .bind(tokenHash)
    .first();
  if (!account) return json({ error: true, message: "Token no reconocido" }, 401);
  const accountId = account.id;

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: true, message: "JSON inválido" }, 400);
  }

  const now = new Date().toISOString();
  const acc = body.account || {};
  const openPositions = Array.isArray(body.open_positions) ? body.open_positions : [];
  const closedTrades = Array.isArray(body.closed_trades) ? body.closed_trades : [];

  const stmts = [];

  // Snapshot de cuenta (una fila por push, no por tick).
  stmts.push(
    env.DB.prepare(
      `INSERT INTO account_snapshots (account_id, ts, balance, equity, margin, free_margin, margin_level)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(accountId, now, acc.balance ?? null, acc.equity ?? null, acc.margin ?? null,
           acc.free_margin ?? null, acc.margin_level ?? null)
  );

  // Posiciones abiertas: se reemplaza el conjunto entero de esta cuenta en
  // cada push (MT5 siempre manda el estado actual completo, no deltas).
  stmts.push(env.DB.prepare("DELETE FROM open_positions WHERE account_id = ?").bind(accountId));
  for (const p of openPositions) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO open_positions
         (account_id, ticket, symbol, type, volume, open_price, open_time, sl, tp, profit, swap, magic, comment, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(accountId, String(p.ticket), p.symbol ?? null, p.type ?? null, p.volume ?? null,
             p.open_price ?? null, p.open_time ?? null, p.sl ?? null, p.tp ?? null,
             p.profit ?? null, p.swap ?? null, p.magic ?? null, p.comment ?? null, now)
    );
  }

  // Operaciones cerradas: solo se añaden, nunca se borran. INSERT OR IGNORE
  // resuelve el "ya la tenía" gratis via la clave primaria (account_id, ticket).
  for (const t of closedTrades) {
    stmts.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO closed_trades
         (account_id, ticket, symbol, type, volume, open_price, close_price, open_time, close_time,
          profit, commission, swap, magic, comment, inserted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(accountId, String(t.ticket), t.symbol ?? null, t.type ?? null, t.volume ?? null,
             t.open_price ?? null, t.close_price ?? null, t.open_time ?? null, t.close_time ?? null,
             t.profit ?? null, t.commission ?? null, t.swap ?? null, t.magic ?? null,
             t.comment ?? null, now)
    );
  }

  stmts.push(env.DB.prepare("UPDATE accounts SET last_seen_at = ? WHERE id = ?").bind(now, accountId));

  await env.DB.batch(stmts);
  return json({ error: false, received: { open_positions: openPositions.length, closed_trades: closedTrades.length } });
}

async function handleAccounts(env) {
  const { results } = await env.DB.prepare(
    `SELECT a.id, a.mt5_login, a.label, a.broker, a.currency, a.last_seen_at,
            s.balance, s.equity, s.margin_level
     FROM accounts a
     LEFT JOIN account_snapshots s ON s.account_id = a.id AND s.ts = (
       SELECT MAX(ts) FROM account_snapshots WHERE account_id = a.id
     )
     ORDER BY a.label`
  ).all();
  return json({ error: false, accounts: results });
}

async function handlePositions(env, accountId) {
  const { results } = await env.DB.prepare(
    "SELECT * FROM open_positions WHERE account_id = ? ORDER BY open_time DESC"
  ).bind(accountId).all();
  return json({ error: false, positions: results });
}

async function handleTrades(env, accountId, limit) {
  const { results } = await env.DB.prepare(
    "SELECT * FROM closed_trades WHERE account_id = ? ORDER BY close_time DESC LIMIT ?"
  ).bind(accountId, limit).all();
  return json({ error: false, trades: results });
}

async function handleEquity(env, accountId, limit) {
  const { results } = await env.DB.prepare(
    "SELECT ts, balance, equity FROM account_snapshots WHERE account_id = ? ORDER BY ts DESC LIMIT ?"
  ).bind(accountId, limit).all();
  return json({ error: false, snapshots: results.reverse() });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === "/ingest" && request.method === "POST") {
        return await handleIngest(request, env);
      }
      if (path === "/api/accounts" && request.method === "GET") {
        return await handleAccounts(env);
      }
      const posMatch = path.match(/^\/api\/accounts\/(\d+)\/positions$/);
      if (posMatch && request.method === "GET") {
        return await handlePositions(env, Number(posMatch[1]));
      }
      const tradesMatch = path.match(/^\/api\/accounts\/(\d+)\/trades$/);
      if (tradesMatch && request.method === "GET") {
        const limit = Math.min(500, Number(url.searchParams.get("limit") || 50));
        return await handleTrades(env, Number(tradesMatch[1]), limit);
      }
      const equityMatch = path.match(/^\/api\/accounts\/(\d+)\/equity$/);
      if (equityMatch && request.method === "GET") {
        const limit = Math.min(2000, Number(url.searchParams.get("limit") || 200));
        return await handleEquity(env, Number(equityMatch[1]), limit);
      }
    } catch (err) {
      return json({ error: true, message: String(err) }, 500);
    }

    // Cualquier otra ruta: panel estático (public/index.html y compañía).
    return env.ASSETS.fetch(request);
  },
};
