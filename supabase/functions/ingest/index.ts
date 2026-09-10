// Edge Function que recibe los datos en vivo del EA reportero (POST) y los
// guarda en Supabase. Usa la SERVICE ROLE key (variable de entorno ya provista
// por Supabase a toda Edge Function, no hay que configurarla a mano) para
// poder escribir saltándose Row Level Security -- el control de acceso aquí
// lo hace el token por cuenta (hasheado), no RLS.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: true, message: "Solo POST" }, 405);
  }

  const auth = req.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return json({ error: true, message: "Falta token" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const tokenHash = await sha256Hex(token);
  const { data: account, error: accErr } = await supabase
    .from("accounts")
    .select("id")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (accErr) return json({ error: true, message: accErr.message }, 500);
  if (!account) return json({ error: true, message: "Token no reconocido" }, 401);
  const accountId = account.id;

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: true, message: "JSON inválido" }, 400);
  }

  const now = new Date().toISOString();
  const acc = body.account || {};
  const openPositions: any[] = Array.isArray(body.open_positions) ? body.open_positions : [];
  const closedTrades: any[] = Array.isArray(body.closed_trades) ? body.closed_trades : [];

  // Snapshot de cuenta: una fila por push, no por tick.
  const { error: snapErr } = await supabase.from("account_snapshots").insert({
    account_id: accountId,
    ts: now,
    balance: acc.balance ?? null,
    equity: acc.equity ?? null,
    margin: acc.margin ?? null,
    free_margin: acc.free_margin ?? null,
    margin_level: acc.margin_level ?? null,
  });
  if (snapErr) return json({ error: true, message: snapErr.message }, 500);

  // Posiciones abiertas: se reemplaza el conjunto entero de esta cuenta en
  // cada push (MT5 siempre manda el estado actual completo, no deltas).
  const { error: delErr } = await supabase.from("open_positions").delete().eq("account_id", accountId);
  if (delErr) return json({ error: true, message: delErr.message }, 500);

  if (openPositions.length) {
    const rows = openPositions.map((p) => ({
      account_id: accountId,
      ticket: String(p.ticket),
      symbol: p.symbol ?? null,
      type: p.type ?? null,
      volume: p.volume ?? null,
      open_price: p.open_price ?? null,
      open_time: p.open_time || null,
      sl: p.sl ?? null,
      tp: p.tp ?? null,
      profit: p.profit ?? null,
      swap: p.swap ?? null,
      magic: p.magic ?? null,
      comment: p.comment ?? null,
      updated_at: now,
    }));
    const { error } = await supabase.from("open_positions").insert(rows);
    if (error) return json({ error: true, message: error.message }, 500);
  }

  // Operaciones cerradas: solo se añaden, nunca se borran. upsert con
  // ignoreDuplicates resuelve el "ya la tenía" gratis via la clave primaria
  // (account_id, ticket).
  if (closedTrades.length) {
    const rows = closedTrades.map((t) => ({
      account_id: accountId,
      ticket: String(t.ticket),
      symbol: t.symbol ?? null,
      type: t.type ?? null,
      volume: t.volume ?? null,
      open_price: t.open_price ?? null,
      close_price: t.close_price ?? null,
      open_time: t.open_time || null,
      close_time: t.close_time || null,
      profit: t.profit ?? null,
      commission: t.commission ?? null,
      swap: t.swap ?? null,
      magic: t.magic ?? null,
      comment: t.comment ?? null,
      inserted_at: now,
    }));
    const { error } = await supabase
      .from("closed_trades")
      .upsert(rows, { onConflict: "account_id,ticket", ignoreDuplicates: true });
    if (error) return json({ error: true, message: error.message }, 500);
  }

  const { error: touchErr } = await supabase
    .from("accounts")
    .update({ last_seen_at: now })
    .eq("id", accountId);
  if (touchErr) return json({ error: true, message: touchErr.message }, 500);

  return json({
    error: false,
    received: { open_positions: openPositions.length, closed_trades: closedTrades.length },
  });
});
