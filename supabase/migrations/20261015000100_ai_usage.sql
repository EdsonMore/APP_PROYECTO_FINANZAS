-- =============================================================================
-- 5C-Infra · Límite diario de la IA: ai_usage + ai_usage_today() + ai_record_use()
-- =============================================================================
-- La Edge Function ai-proxy cuenta las consultas a Gemini por usuario y día.
--   · Solo un contador: nunca preguntas, hechos ni respuestas.
--   · El "día" es el de Lima (America/Lima): el límite se renueva a la
--     medianoche del usuario, no a la de UTC.
--   · RLS: cada usuario ve solo sus filas; nadie inserta ni modifica directo.
--     Solo ai_record_use() suma, y solo para auth.uid() (sale del JWT).
--   · La función corre con el JWT del usuario: no hace falta service_role.
--   · Al borrar la cuenta (delete_account), el ON DELETE CASCADE borra sus filas.
--   · search_path vacío: todo con nombre calificado.
-- Aplicar primero en saldoclaro-test y correr supabase/tests/verificar_ai_usage.sql.
-- =============================================================================

begin;

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

drop policy if exists ai_usage_select_own on public.ai_usage;
create policy ai_usage_select_own on public.ai_usage
  for select to authenticated
  using (user_id = auth.uid());
-- Sin políticas de insert/update/delete: nadie escribe directo.

revoke all on table public.ai_usage from public, anon, authenticated;
grant select on table public.ai_usage to authenticated;

-- Día de Lima de un instante (por defecto, ahora). Con parámetro para poder
-- probar el cambio de día sin esperar a la medianoche.
create or replace function public.ai_day(ts timestamptz default now())
returns date
language sql
stable
set search_path = ''
as $$
  select (ts at time zone 'America/Lima')::date;
$$;

-- Consultas de hoy del usuario de la sesión (0 si no hay fila).
create or replace function public.ai_usage_today()
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select u.count from public.ai_usage u where u.user_id = auth.uid() and u.day = public.ai_day()),
    0);
$$;

-- Suma 1 a la fila de hoy del usuario de la sesión y devuelve el total.
create or replace function public.ai_record_use()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  total integer;
begin
  if uid is null then
    raise exception 'ai_record_use: sin sesión' using errcode = '28000';
  end if;
  insert into public.ai_usage (user_id, day, count)
    values (uid, public.ai_day(), 1)
  on conflict (user_id, day) do update set count = public.ai_usage.count + 1
  returning count into total;
  return total;
end;
$$;

revoke all on function public.ai_day(timestamptz) from public, anon;
revoke all on function public.ai_usage_today() from public, anon;
revoke all on function public.ai_record_use() from public, anon;
grant execute on function public.ai_day(timestamptz) to authenticated;
grant execute on function public.ai_usage_today() to authenticated;
grant execute on function public.ai_record_use() to authenticated;

commit;
