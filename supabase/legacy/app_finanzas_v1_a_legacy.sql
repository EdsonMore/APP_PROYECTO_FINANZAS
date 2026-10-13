-- =============================================================================
-- Apartar el esquema de la v1 (SOLO en el proyecto viejo app-finanzas).
-- NO es una migración: saldoclaro-prod se creó limpio, sin esto.
-- =============================================================================
-- La v1 (tag git v1-supabase) creó en `public` 7 tablas, 4 funciones y un
-- trigger sobre auth.users. Dos chocan con la Fase 3:
--   · public.categories existe con otras columnas (la v3 la necesita limpia).
--   · on_auth_user_created inserta en public.profiles en cada registro: si esa
--     tabla se mueve o cambia, el registro de usuarios nuevos FALLA.
-- Además, public.insert_transaction(p_user_id …) queda expuesta como RPC.
--
-- Esto NO borra datos: mueve todo a un esquema `legacy_v1`, que la API de
-- Supabase no publica. Cuando confirmes que no hace falta, se borra con:
--   drop schema legacy_v1 cascade;
--
-- No correr en saldoclaro-test (ahí no existe la v1).
--
-- Antes de correrlo, el DIAGNÓSTICO (solo lectura) dice qué hay. Es una sola
-- consulta porque el SQL editor muestra solo el resultado de la última, y no
-- falla aunque las tablas no existan. Copiar sin los "-- " y correr aparte:
--
--   select 'tabla public' as tipo, c.relname as nombre,
--          case when c.relname in ('transactions','categories','accounts','account_sources',
--                                   'billing_cycles','splits','profiles')
--               then (xpath('/row/n/text()', query_to_xml(
--                       format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text
--          end as filas
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind = 'r'
--   union all
--   select 'funcion public', p.proname, null
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--   union all
--   select 'trigger auth.users', t.tgname, null
--     from pg_trigger t
--    where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal
--   union all
--   select 'esquema', nspname, null from pg_namespace where nspname = 'legacy_v1'
--   order by 1, 2;
--
-- VERIFICACIÓN DESPUÉS (otra consulta sola):
--
--   select 'legacy_v1' as donde, c.relname as nombre,
--          (xpath('/row/n/text()', query_to_xml(
--             format('select count(*) as n from legacy_v1.%I', c.relname), false, true, '')))[1]::text as filas
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'legacy_v1' and c.relkind = 'r'
--   union all
--   select 'tabla public (debería no haber ninguna)', c.relname, null
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind = 'r'
--   union all
--   select 'funcion public (debería no haber ninguna)', p.proname, null
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--   union all
--   select 'trigger auth.users (debería no haber ninguno)', t.tgname, null
--     from pg_trigger t
--    where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal
--   order by 1, 2;
--
-- DESHACER (si hiciera falta): mover cada tabla y función de vuelta con
--   alter table legacy_v1.<tabla> set schema public;
-- y recrear el trigger on_auth_user_created (está en el tag git v1-supabase).
-- -----------------------------------------------------------------------------

begin;

create schema if not exists legacy_v1;
revoke all on schema legacy_v1 from public, anon, authenticated;

-- El trigger de registro primero: después de mover profiles, fallaría.
drop trigger if exists on_auth_user_created on auth.users;

alter table if exists public.splits set schema legacy_v1;
alter table if exists public.transactions set schema legacy_v1;
alter table if exists public.billing_cycles set schema legacy_v1;
alter table if exists public.account_sources set schema legacy_v1;
alter table if exists public.accounts set schema legacy_v1;
alter table if exists public.categories set schema legacy_v1;
alter table if exists public.profiles set schema legacy_v1;

-- ALTER FUNCTION no admite IF EXISTS: se mueve cada una solo si existe.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.handle_new_user()',
    'public.set_updated_at()',
    'public.adjust_account_balance(uuid, numeric)',
    'public.insert_transaction(uuid, uuid, uuid, uuid, numeric, text, text, text, text, text, timestamptz)'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('alter function %s set schema legacy_v1', f);
    end if;
  end loop;
end;
$$;

commit;
