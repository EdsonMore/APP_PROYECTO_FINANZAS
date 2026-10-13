-- =============================================================================
-- Verificación de delete_account() · SOLO en saldoclaro-test
-- =============================================================================
-- Cómo correrlo:
--   1. En saldoclaro-test crea un usuario C de prueba (Add user, Auto Confirm)
--      y otro D. Reemplaza:
--        cccccccc-cccc-cccc-cccc-cccccccccccc  →  UUID de C
--        dddddddd-dddd-dddd-dddd-dddddddddddd  →  UUID de D
--   2. Ejecuta todo en el SQL editor.
-- Resultado esperado: "delete_account OK".
-- Termina en ROLLBACK: C NO queda borrado de verdad. Para probarlo de punta a
-- punta (borrado real), cambia el último ROLLBACK por COMMIT con un usuario
-- desechable y revisa que desaparezca de Authentication → Users.
-- =============================================================================

begin;

-- C y D tienen datos.
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);
set local role authenticated;
insert into public.categories (id, name, icon, color_hex, sort_order, updated_at)
  values ('comida', 'Comida', 'restaurant', 'cat:1', 0, 1000);
insert into public.entries (id, kind, amount_cents, occurred_on, category_id, created_at, updated_at)
  values ('e1', 'expense', 1250, '2026-10-08', 'comida', 1000, 1000);
insert into public.budgets (category_id, cap_cents, updated_at) values ('comida', 60000, 1000);
insert into public.settings (mode, updated_at) values ('stable', 1000);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}', true);
set local role authenticated;
insert into public.categories (id, name, icon, color_hex, sort_order, updated_at)
  values ('comida', 'Comida', 'restaurant', 'cat:1', 0, 1000);
insert into public.settings (mode, updated_at) values ('variable', 1000);

-- C borra su cuenta.
reset role;
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);
set local role authenticated;
select public.delete_account();

-- Verificación como postgres (ve todo, sin RLS).
reset role;
do $$
begin
  assert not exists (select 1 from auth.users where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    'C debería haber desaparecido de auth.users';
  assert not exists (select 1 from public.entries where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    'los movimientos de C deberían haberse borrado';
  assert not exists (select 1 from public.categories where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    'las categorías de C deberían haberse borrado';
  assert not exists (select 1 from public.budgets where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    'los techos de C deberían haberse borrado';
  assert not exists (select 1 from public.settings where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    'los ajustes de C deberían haberse borrado';
  assert exists (select 1 from auth.users where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
    'D NO debería verse afectado';
  assert (select count(*) from public.categories where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') = 1,
    'los datos de D deberían seguir';
end $$;

-- Sin sesión (claims sin sub) delete_account falla aunque el rol pudiera llamarla.
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  begin
    perform public.delete_account();
    assert false, 'delete_account sin sub debería fallar';
  exception when sqlstate '28000' then
    null;
  end;
end $$;

reset role;
select 'delete_account OK' as resultado;

rollback;
