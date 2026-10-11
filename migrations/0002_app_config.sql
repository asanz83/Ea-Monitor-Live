-- Config de ea_monitor (antes config.json local) — una sola fila, todo el
-- contenido en una columna jsonb para no tener que rediseñar el resto del
-- código que hoy trata la config como un único dict. Solo la toca el backend
-- Flask con la service_role key (nunca el navegador), así que RLS se deja
-- activado SIN políticas: deniega todo por defecto a anon/authenticated, y
-- service_role la salta igualmente (igual que ya hace con las demás tablas).
create table app_config (
  id bigint primary key default 1,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint app_config_singleton check (id = 1)
);

alter table app_config enable row level security;

insert into app_config (id, data) values (1, '{}'::jsonb);
