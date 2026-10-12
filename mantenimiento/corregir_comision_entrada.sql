-- CORRECCION PUNTUAL (NO es una migracion: no ejecutar al recrear la base de datos).
-- Hasta EA_Reporter v1.13 las operaciones llegaban SOLO con la comision de la pata de cierre; el neto
-- (profit + commission + swap) salia ~mitad de comision de mas. Comprobado el 2026-10-12: la comision
-- por lote de las filas del reportero es exactamente la mitad que la de las importadas (bf_...) en las
-- 20 combinaciones cuenta+simbolo, y en MT5 las dos patas son iguales.
-- A partir de la v1.14 el EA ya manda las dos patas. Este script duplica la comision de las filas
-- guardadas ANTES de actualizar el EA de CADA cuenta.
--
-- ORDEN (importante, se ejecuta UNA SOLA VEZ):
--   1) Instalar EA_Reporter v1.14 en las cuentas (pueden ser en dias distintos).
--   2) Anotar, POR CUENTA, la hora UTC en que quedo instalada la v1.14: ese es su CORTE. Una cuenta con
--      v1.13 sigue mandando la comision a la mitad, asi que cada una necesita su propio corte.
--      Si hay cuentas sin actualizar, se dejan fuera de la lista (se corrigen cuando se actualicen).
--   3) Rellenar la lista `cortes` de abajo (account_id = 2..10, ver cuentas.csv del ZIP).
--   4) Ejecutar el SELECT de comprobacion; si las cifras cuadran, el UPDATE (quitando los "--").
--   5) Avisar para fijar COMISION_CORREGIDA_UTC en export_analisis.py (columna `comision_completa` del ZIP).
-- Si se ejecuta dos veces, la comision queda a x4: antes de repetir, comprobar con el SELECT.
--
-- Hora UTC = hora de Espana - 2 h en horario de verano (CEST), - 1 h en invierno (CET).

-- 1) Comprobacion (no cambia nada)
with cortes(account_id, corte) as (values
  (2,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- fondeada 166081
  (3,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- incubacion
  (4,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- incubacion2
  (5,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- XAUUSD Incubacion
  (6,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- DEMO NDX
  (7,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- USDJPY_incubacion
  (8,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- H4 Incubacion
  (9,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- Incubacion 001
  (10, timestamptz '2026-10-DD HH:MM:SS+00')    -- DARWINEX ZERO
)
select c.account_id, count(*) as filas, round(sum(t.commission)::numeric, 2) as comision_actual,
       round((2 * sum(t.commission))::numeric, 2) as comision_tras_corregir
from closed_trades t join cortes c on c.account_id = t.account_id
where t.ticket not like 'bf\_%' and t.commission <> 0 and t.inserted_at < c.corte
group by c.account_id order by c.account_id;

-- 2) Correccion (ejecutar una sola vez, con la MISMA lista `cortes`)
-- with cortes(account_id, corte) as (values
--   (2,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- fondeada 166081
--   (3,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- incubacion
--   (4,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- incubacion2
--   (5,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- XAUUSD Incubacion
--   (6,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- DEMO NDX
--   (7,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- USDJPY_incubacion
--   (8,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- H4 Incubacion
--   (9,  timestamptz '2026-10-DD HH:MM:SS+00'),   -- Incubacion 001
--   (10, timestamptz '2026-10-DD HH:MM:SS+00')    -- DARWINEX ZERO
-- )
-- update closed_trades t set commission = t.commission * 2
-- from cortes c
-- where c.account_id = t.account_id and t.ticket not like 'bf\_%' and t.commission <> 0 and t.inserted_at < c.corte;

-- NOTA 2026-10-12: la v1.14 NO funciono (el EA solo veia el historial de los ultimos minutos y no encontraba
-- la entrada de posiciones abiertas hace horas: seguia mandando la comision a la mitad, y open_price/open_time
-- vacios). La correccion real es la v1.15 (HistorySelectByPosition). Los cortes deben ser las horas en que
-- quedo instalada la v1.15 en cada cuenta, NO la v1.14. ANTES del UPDATE comprobar que los primeros cierres
-- nuevos ya llegan con la comision completa (p. ej. NDX ~ -5.5 por lote, no -2.75) y con open_price relleno.
