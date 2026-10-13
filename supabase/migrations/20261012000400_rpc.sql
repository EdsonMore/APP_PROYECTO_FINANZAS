-- =============================================================================
-- 004 · RPC delete_account(): el usuario borra su cuenta y todos sus datos
-- =============================================================================
-- Lo exige Google Play para apps que permiten crear cuenta.
--   · security definer: corre con los permisos del dueño de la función
--     (postgres), que puede borrar en auth.users. Así la app NO necesita la
--     service_role key.
--   · Borra SOLO a quien llama: auth.uid() sale del JWT de la sesión; no
--     recibe parámetros que alguien pueda falsear.
--   · Sin sesión, falla (auth.uid() es null).
--   · Al borrar de auth.users, el ON DELETE CASCADE de las 5 tablas borra
--     todas sus filas.
--   · search_path vacío: todo con nombre calificado (evita que un objeto con
--     el mismo nombre en otro esquema se use en su lugar).
--   · Los datos del teléfono no se tocan: eso lo decide la app (3B).
-- =============================================================================

begin;

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'delete_account: sin sesión' using errcode = '28000';
  end if;
  delete from auth.users where id = uid;
end;
$$;

-- Por defecto Postgres deja ejecutar funciones a PUBLIC: se cierra y se abre
-- solo para usuarios con sesión.
revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

commit;
