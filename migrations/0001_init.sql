-- Esquema inicial (Postgres/Supabase). Pegar y ejecutar en Supabase Dashboard >
-- SQL Editor > New query, una sola vez.

create table accounts (
  id            bigint generated always as identity primary key,
  mt5_login     text not null unique,
  label         text,
  broker        text,
  currency      text,
  token_hash    text not null,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz
);

create table open_positions (
  account_id   bigint not null references accounts(id) on delete cascade,
  ticket       text not null,
  symbol       text,
  type         text,
  volume       double precision,
  open_price   double precision,
  open_time    timestamptz,
  sl           double precision,
  tp           double precision,
  profit       double precision,
  swap         double precision,
  magic        bigint,
  comment      text,
  updated_at   timestamptz not null default now(),
  primary key (account_id, ticket)
);

create table closed_trades (
  account_id   bigint not null references accounts(id) on delete cascade,
  ticket       text not null,
  symbol       text,
  type         text,
  volume       double precision,
  open_price   double precision,
  close_price  double precision,
  open_time    timestamptz,
  close_time   timestamptz,
  profit       double precision,
  commission   double precision,
  swap         double precision,
  magic        bigint,
  comment      text,
  inserted_at  timestamptz not null default now(),
  primary key (account_id, ticket)
);

create table account_snapshots (
  account_id    bigint not null references accounts(id) on delete cascade,
  ts            timestamptz not null,
  balance       double precision,
  equity        double precision,
  margin        double precision,
  free_margin   double precision,
  margin_level  double precision,
  primary key (account_id, ts)
);

create index idx_closed_trades_account on closed_trades(account_id, close_time);
create index idx_snapshots_account on account_snapshots(account_id, ts);

-- Row Level Security: el panel lee estas tablas con el usuario autenticado
-- (login por email, ver README paso 7). El Edge Function que recibe los datos
-- del EA usa la service_role key, que SIEMPRE salta RLS -- por eso aquí basta
-- con permitir lectura a cualquier usuario autenticado, sin filtrar por
-- columnas de "dueño" (solo hay una persona usando esto).
alter table accounts enable row level security;
alter table open_positions enable row level security;
alter table closed_trades enable row level security;
alter table account_snapshots enable row level security;

create policy "authenticated read accounts" on accounts
  for select to authenticated using (true);
create policy "authenticated read open_positions" on open_positions
  for select to authenticated using (true);
create policy "authenticated read closed_trades" on closed_trades
  for select to authenticated using (true);
create policy "authenticated read account_snapshots" on account_snapshots
  for select to authenticated using (true);

-- Necesario para que el panel reciba actualizaciones en vivo (Supabase
-- Realtime solo emite cambios de tablas añadidas a esta publicación).
alter publication supabase_realtime add table open_positions;
alter publication supabase_realtime add table closed_trades;
alter publication supabase_realtime add table account_snapshots;
alter publication supabase_realtime add table accounts;
