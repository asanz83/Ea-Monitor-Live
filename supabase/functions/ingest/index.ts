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

// Avisos de apertura/cierre de operaciones: esta funcion NO habla con Telegram
// directamente; le pasa los eventos a la app de ea_monitor (que ya tiene el bot
// configurado y sabe formatear el mensaje). Necesita el secreto
// ALERTS_CRON_SECRET en los secretos de las Edge Functions de Supabase; si no
// esta, no avisa y todo lo demas funciona igual.
const APP_URL = "https://ea-monitor-app-1n94.onrender.com";

function notifyTradeEvents(payload: unknown) {
  const secret = Deno.env.get("ALERTS_CRON_SECRET");
  if (!secret) return;
  const p = fetch(`${APP_URL}/api/alerts/trade-event?key=${encodeURIComponent(secret)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  }).catch(() => {});
  // waitUntil: seguir el envio sin retrasar la respuesta al EA (que solo espera 5 s)
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(p);
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
    .select("id,last_seen_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (accErr) return json({ error: true, message: accErr.message }, 500);
  if (!account) return json({ error: true, message: "Token no reconocido" }, 401);
  const accountId = account.id;

  let body: any;
  const rawText = await req.text();
  try {
    body = JSON.parse(rawText);
  } catch (e) {
    // Devuelve un trozo del texto recibido para poder ver a simple vista
    // qué parte del JSON generado por el EA no es válida (temporal, solo
    // para diagnosticar -- quitar el snippet una vez esté todo estable).
    return json({ error: true, message: "JSON inválido: " + String(e).slice(0, 120), snippet: rawText.slice(0, 300) }, 400);
  }

  const now = new Date().toISOString();

  // Envio aparte de velas (EA_Reporter v1.1): un POST por simbolo con posicion
  // abierta, cada pocos minutos. NO toca snapshots ni posiciones -- sin este
  // desvio, un cuerpo sin "open_positions" se interpretaria como "no hay
  // ninguna abierta" y borraria las posiciones de la cuenta.
  if (body.candles_only) {
    const sym = String(body.symbol || "");
    const list: any[] = Array.isArray(body.candles) ? body.candles : [];
    if (!sym || !list.length) return json({ error: true, message: "Sin velas" }, 400);
    const rows = list
      .filter((c) => c && c.tf && Array.isArray(c.bars) && c.bars.length)
      .map((c) => ({ account_id: accountId, symbol: sym, tf: String(c.tf), bars: c.bars, updated_at: now }));
    if (!rows.length) return json({ error: true, message: "Velas vacias" }, 400);
    const { error } = await supabase.from("candles").upsert(rows, { onConflict: "account_id,symbol,tf" });
    if (error) return json({ error: true, message: error.message }, 500);
    return json({ error: false, received: { candles: rows.length } });
  }

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

  // Estado anterior, para detectar aperturas/cierres NUEVOS. Solo se avisa si la
  // cuenta venia reportando hace poco (<10 min): con la primera carga de una
  // cuenta, o tras una caida larga, se inundaria de avisos de cosas antiguas.
  const { data: prevPos } = await supabase
    .from("open_positions").select("ticket,symbol,comment,magic").eq("account_id", accountId);
  const prevByTicket = new Map((prevPos ?? []).map((p: any) => [String(p.ticket), p]));
  const recentlySeen = !!account.last_seen_at &&
    (Date.now() - Date.parse(account.last_seen_at)) < 10 * 60 * 1000;
  const openedEvents = recentlySeen
    ? openPositions.filter((p) => !prevByTicket.has(String(p.ticket)))
    : [];

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

  // Limpia las velas de simbolos que ya no tienen posicion abierta (si la
  // tabla aun no existe, el error se ignora a proposito: no debe romper el
  // envio principal).
  {
    const symbols = [...new Set(openPositions.map((p) => p.symbol).filter(Boolean))];
    let q = supabase.from("candles").delete().eq("account_id", accountId);
    if (symbols.length) q = q.not("symbol", "in", `(${symbols.map((s) => `"${s}"`).join(",")})`);
    await q;
  }

  // Operaciones cerradas: solo se añaden, nunca se borran. upsert con
  // ignoreDuplicates resuelve el "ya la tenía" gratis via la clave primaria
  // (account_id, ticket).
  let closedEvents: any[] = [];
  if (closedTrades.length) {
    const sent = closedTrades.map((t) => String(t.ticket));
    const { data: already } = await supabase
      .from("closed_trades").select("ticket").eq("account_id", accountId).in("ticket", sent);
    const alreadySet = new Set((already ?? []).map((r: any) => String(r.ticket)));
    if (recentlySeen) {
      closedEvents = closedTrades
        .filter((t) => !alreadySet.has(String(t.ticket)))
        // El comentario del cierre suele ser "[tp ...]"/"[sl ...]"; el nombre
        // del EA esta en el de la posicion cuando estaba abierta.
        .map((t) => ({ ...t, ea_comment: prevByTicket.get(String(t.ticket))?.comment || t.comment }));
    }
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

  if (openedEvents.length || closedEvents.length) {
    notifyTradeEvents({ account_id: accountId, opened: openedEvents, closed: closedEvents });
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
