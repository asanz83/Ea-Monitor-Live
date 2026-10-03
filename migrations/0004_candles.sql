-- Velas de los simbolos con posicion abierta, enviadas por EA_Reporter v1.1
-- para dibujar el grafico de velas con la entrada marcada en ea_monitor.
-- Pegar y ejecutar una sola vez en Supabase > SQL Editor.
-- Una fila por (cuenta, simbolo, timeframe); `bars` es un array JSON de
-- [tiempo_servidor_epoch, open, high, low, close]. Se REEMPLAZA entera en
-- cada envio (no se acumula), y la Edge Function borra las filas de los
-- simbolos que ya no tienen posicion abierta.
create table if not exists candles (
  account_id  bigint not null references accounts(id) on delete cascade,
  symbol      text   not null,
  tf          text   not null,
  bars        jsonb  not null,
  updated_at  timestamptz not null default now(),
  primary key (account_id, symbol, tf)
);

alter table candles enable row level security;
create policy "candles_read_authenticated" on candles
  for select to authenticated using (true);
