-- RECONSTRUIDA (2026-10-11): estas dos piezas se crearon a mano en el SQL Editor de Supabase
-- y su SQL original no se guardó. Esto se ha deducido de cómo las usa ea_monitor (app.py), así
-- que puede no ser idéntico al original. Para el esquema real, mira `esquema_openapi.json` dentro
-- de cualquier copia de seguridad generada con backup_supabase.py.
--
-- Es seguro ejecutarla en un proyecto que ya las tiene (usa "if not exists"/"or replace").

-- Carteras simuladas guardadas desde la pestaña "Portfolio simulado".
create table if not exists virtual_portfolios (
  id text primary key,                    -- uuid generado por la app
  name text not null,
  ea_keys jsonb not null default '[]'::jsonb,   -- lista de EAs de la cartera
  initial_capital double precision not null,
  created_at timestamptz not null default now(),
  notes text
);
alter table virtual_portfolios enable row level security;   -- solo el backend (service_role)

-- Resumen por cuenta de closed_trades. Hoy la app recalcula casi todo desde las operaciones
-- (beneficio NETO con comisión y swap); esta vista queda como respaldo y para first/last_trade_at.
create or replace view account_trade_stats as
select
  account_id,
  count(*)                                                        as trades,
  count(*) filter (where profit > 0)                              as wins,
  coalesce(sum(profit) filter (where profit > 0), 0)              as gross_profit,
  coalesce(-sum(profit) filter (where profit < 0), 0)             as gross_loss,
  avg(profit)                                                     as expectancy,
  min(close_time)                                                 as first_trade_at,
  max(close_time)                                                 as last_trade_at
from closed_trades
group by account_id;

grant select on account_trade_stats to service_role;
