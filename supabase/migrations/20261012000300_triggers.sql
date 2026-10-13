-- =============================================================================
-- 003 · Trigger de sync: last-write-wins + server_updated_at
-- =============================================================================
-- Una sola función para las 5 tablas, antes de INSERT y UPDATE:
--   · UPDATE con un updated_at MENOR O IGUAL al guardado: se descarta la fila
--     (return null). Así el teléfono hace un upsert simple y el servidor
--     decide: gana el cambio más nuevo según el reloj del teléfono que lo hizo.
--     Igual = el mismo cambio reenviado (reintento): no hace nada.
--   · user_id no cambia nunca en un UPDATE (RLS ya lo impide; esto es una
--     segunda barrera).
--   · server_updated_at siempre lo pone el servidor; lo que mande el teléfono
--     se ignora. clock_timestamp() (no now()): cada fila de un mismo lote
--     recibe una hora distinta y creciente.
-- Nota para 3C: una transacción que confirma tarde puede dejar un
-- server_updated_at un poco anterior al último cursor leído; el teléfono baja
-- con unos segundos de solapamiento y, como aplicar es idempotente, no se
-- pierde nada.
-- =============================================================================

begin;

create or replace function public.sync_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at <= old.updated_at then
      return null;
    end if;
    new.user_id := old.user_id;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

-- Es una función de trigger: nadie debe poder llamarla por su cuenta.
revoke all on function public.sync_before_write() from public, anon, authenticated;

create trigger categories_sync_before_write
  before insert or update on public.categories
  for each row execute function public.sync_before_write();
create trigger sources_sync_before_write
  before insert or update on public.sources
  for each row execute function public.sync_before_write();
create trigger entries_sync_before_write
  before insert or update on public.entries
  for each row execute function public.sync_before_write();
create trigger budgets_sync_before_write
  before insert or update on public.budgets
  for each row execute function public.sync_before_write();
create trigger settings_sync_before_write
  before insert or update on public.settings
  for each row execute function public.sync_before_write();

commit;
