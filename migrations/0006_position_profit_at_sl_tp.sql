-- EA_Reporter v1.12: dinero que se ganaria/perderia en cada posicion abierta si el
-- precio llega a su TP o a su SL (lo calcula MT5 con OrderCalcProfit). Se ve en el
-- grafico de velas de ea_monitor junto a las lineas de SL/TP.
--
-- Ejecutar UNA vez en el SQL Editor de Supabase, ANTES de actualizar el EA en las
-- cuentas (si la funcion no encuentra las columnas, reintenta sin ellas y todo lo
-- demas sigue funcionando).
alter table open_positions
  add column if not exists profit_sl double precision,
  add column if not exists profit_tp double precision;
