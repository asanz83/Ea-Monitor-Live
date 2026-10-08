-- Estado de los permisos de trading automatico por cuenta (EA_Reporter v1.11).
-- La Edge Function `ingest` lo usa para avisar por Telegram cuando el servidor
-- del broker deshabilita los EAs (RetCode 10026 "AutoTrading disabled by server")
-- o cuando el boton "Trading algoritmico" del terminal esta apagado.
--
-- Ejecutar UNA vez en el SQL Editor de Supabase. Es seguro hacerlo antes o despues
-- de desplegar la funcion: si las columnas no existen, la funcion simplemente no
-- hace el seguimiento (no rompe el envio normal).
alter table accounts
  add column if not exists expert_state         text,          -- 'ok' | 'server' | 'terminal' (ultimo estado visto)
  add column if not exists expert_state_count   int not null default 0,  -- envios seguidos con ese estado (se confirma al 3o)
  add column if not exists expert_state_since   timestamptz,   -- desde cuando se ve ese estado
  add column if not exists expert_alerted       text,          -- ultimo estado AVISADO por Telegram
  add column if not exists expert_blocked_since timestamptz;   -- inicio del bloqueo avisado (para el "restablecido tras X")
