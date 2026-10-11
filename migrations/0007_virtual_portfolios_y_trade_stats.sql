-- Piezas que se crearon a mano en el SQL Editor de Supabase y no estaban en ninguna migración.
-- Contrastado el 2026-10-11 con el esquema REAL (esquema_openapi.json de backup_supabase.py):
-- tablas, columnas y tipos coinciden. Lo que no se puede ver desde la API (valores por defecto,
-- índices, políticas) es una reconstrucción razonable.
--
-- Es seguro ejecutarla en un proyecto que ya lo tiene todo ("if not exists" / "or replace").

-- 1) Carteras simuladas guardadas desde la pestaña "Portfolio simulado".
create table if not exists virtual_portfolios (
  id text primary key,                          -- uuid generado por la app
  name text not null,
  ea_keys jsonb not null default '[]'::jsonb,   -- lista de EAs de la cartera
  initial_capital double precision not null,
  created_at timestamptz not null default now(),
  notes text
);
alter table virtual_portfolios enable row level security;   -- solo el backend (service_role)

-- 2) Columnas añadidas a mano a tablas ya existentes.
alter table accounts
  add column if not exists alert_is_stale boolean not null default false,   -- aviso "cuenta sin reportar" ya enviado
  add column if not exists alert_last_sent_at timestamptz,
  add column if not exists alert_state jsonb not null default '{}'::jsonb;  -- fondeo_level / pos / retire
alter table ea_backtest_stats
  add column if not exists timeframe text,
  add column if not exists direction text;

-- 3) Vistas de resumen. Hoy la app recalcula casi todo desde las operaciones (beneficio NETO con
--    comisión y swap); estas vistas quedan como respaldo y para first/last_trade_at.
create or replace view account_trade_stats as
select
  account_id,
  count(*)                                            as trades,
  count(*) filter (where profit > 0)                  as wins,
  coalesce(sum(profit) filter (where profit > 0), 0)  as gross_profit,
  coalesce(-sum(profit) filter (where profit < 0), 0) as gross_loss,
  avg(profit)                                         as expectancy,
  min(close_time)                                     as first_trade_at,
  max(close_time)                                     as last_trade_at
from closed_trades
group by account_id;

create or replace view account_equity_stats as
select
  account_id,
  max(equity)                              as peak_equity,
  min(equity)                              as min_equity,
  (array_agg(equity order by ts asc))[1]   as first_equity,
  min(ts)                                  as first_ts,
  (array_agg(equity order by ts desc))[1]  as last_equity
from account_snapshots
group by account_id;

grant select on account_trade_stats, account_equity_stats to service_role;
