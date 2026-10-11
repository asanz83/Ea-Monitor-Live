-- Datos de backtest de SQX, migrados desde los archivos locales (.html/.csv)
-- para que la version de ea_monitor en la nube (Render) no dependa de ningun
-- archivo en el disco de Antonio. Solo los toca el backend Flask con la
-- service_role key, igual que app_config -- no hace falta RLS para lectura
-- publica aqui.
create table ea_backtest_stats (
  ea_name text primary key,
  symbol text,
  profit_factor double precision,
  max_dd_pct double precision,
  win_rate double precision,
  trades int,
  sharpe double precision,
  return_dd double precision,
  yearly_avg_pct double precision,
  max_consec_losses int,
  validation_start_date date,
  validation_label text,
  updated_at timestamptz not null default now()
);

alter table ea_backtest_stats enable row level security;

create table ea_backtest_daily (
  ea_name text not null references ea_backtest_stats(ea_name) on delete cascade,
  date date not null,
  pnl_pct double precision,
  pnl_usd double precision,
  primary key (ea_name, date)
);

alter table ea_backtest_daily enable row level security;

create index ea_backtest_daily_ea_idx on ea_backtest_daily (ea_name);
