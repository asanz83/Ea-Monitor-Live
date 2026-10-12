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
  (2,  timestamptz '2026-10-12 15:30:00+00'),   -- fondeada 166081
  (3,  timestamptz '2026-10-12 15:30:00+00'),   -- incubacion
  (4,  timestamptz '2026-10-12 15:30:00+00'),   -- incubacion2
  (5,  timestamptz '2026-10-12 15:30:00+00'),   -- XAUUSD Incubacion
  (6,  timestamptz '2026-10-12 15:30:00+00'),   -- DEMO NDX
  (7,  timestamptz '2026-10-12 15:30:00+00'),   -- USDJPY_incubacion
  (8,  timestamptz '2026-10-12 15:30:00+00'),   -- H4 Incubacion
  (9,  timestamptz '2026-10-12 15:30:00+00'),   -- Incubacion 001
  (10, timestamptz '2026-10-12 15:30:00+00')    -- DARWINEX ZERO
)
select c.account_id, count(*) as filas, round(sum(t.commission)::numeric, 2) as comision_actual,
       round((2 * sum(t.commission))::numeric, 2) as comision_tras_corregir
from closed_trades t join cortes c on c.account_id = t.account_id
where t.ticket not like 'bf\_%' and t.commission <> 0 and t.inserted_at < c.corte
group by c.account_id order by c.account_id;

-- 2) Correccion (ejecutar una sola vez, con la MISMA lista `cortes`)
-- with cortes(account_id, corte) as (values
--   (2,  timestamptz '2026-10-12 15:30:00+00'),   -- fondeada 166081
--   (3,  timestamptz '2026-10-12 15:30:00+00'),   -- incubacion
--   (4,  timestamptz '2026-10-12 15:30:00+00'),   -- incubacion2
--   (5,  timestamptz '2026-10-12 15:30:00+00'),   -- XAUUSD Incubacion
--   (6,  timestamptz '2026-10-12 15:30:00+00'),   -- DEMO NDX
--   (7,  timestamptz '2026-10-12 15:30:00+00'),   -- USDJPY_incubacion
--   (8,  timestamptz '2026-10-12 15:30:00+00'),   -- H4 Incubacion
--   (9,  timestamptz '2026-10-12 15:30:00+00'),   -- Incubacion 001
--   (10, timestamptz '2026-10-12 15:30:00+00')    -- DARWINEX ZERO
-- )
-- update closed_trades t set commission = t.commission * 2
-- from cortes c
-- where c.account_id = t.account_id and t.ticket not like 'bf\_%' and t.commission <> 0 and t.inserted_at < c.corte;

-- NOTA 2026-10-12: la v1.14 no funciono; la v1.15 (instalada en las 9 cuentas entre las 15:04 y las 15:10 UTC)
-- si: verificado con cierres de las 19:00 hora servidor en incubacion2 (comision -5.89/lote, open_time relleno)
-- y USDJPY_incubacion (-5.02/lote). Corte 15:30 UTC para las 9 cuentas: es posterior a todas las
-- instalaciones y anterior al primer cierre con v1.15 (16:00 UTC); entre las 15:00 y las 16:00 UTC no cerro
-- ninguna operacion, asi que no hay filas con comision completa antes del corte.
