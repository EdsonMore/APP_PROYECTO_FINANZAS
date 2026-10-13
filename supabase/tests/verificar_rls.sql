-- =============================================================================
-- Verificación de RLS y last-write-wins · SOLO en saldoclaro-test
-- =============================================================================
-- Cómo correrlo:
--   1. En saldoclaro-test: Authentication → Users → Add user → Create new user
--      (dos veces, "Auto Confirm User" marcado). Copia los dos UUID.
--   2. Reemplaza en este archivo:
--        aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa  →  UUID del usuario A
--        bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb  →  UUID del usuario B
--   3. Pega todo en el SQL editor y ejecuta.
-- Resultado esperado: una última fila "RLS OK". Si algo falla, el editor
-- muestra el ASSERT que falló y su mensaje.
-- Todo corre en una transacción que termina en ROLLBACK: no queda nada.
-- Cada bloque cambia de usuario con request.jwt.claims (lo que lee auth.uid())
-- y con el rol `authenticated` o `anon`, como haría la app.
-- =============================================================================

begin;

-- ---------------------------------------------------------------- Usuario A
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- A crea sus filas (user_id lo pone el default auth.uid()).
insert into public.categories (id, name, icon, color_hex, sort_order, is_default, updated_at)
  values ('comida', 'Comida', 'restaurant', 'cat:1', 0, true, 1000);
insert into public.sources (id, name, icon, color_hex, sort_order, is_default, updated_at)
  values ('chamba', 'Chamba', 'payments', '#047857', 0, true, 1000);
insert into public.entries (id, kind, amount_cents, occurred_on, category_id, created_at, updated_at)
  values ('e1', 'expense', 1250, '2026-10-08', 'comida', 1000, 1000);
insert into public.budgets (category_id, cap_cents, updated_at) values ('comida', 60000, 1000);
insert into public.settings (mode, updated_at) values ('variable', 1000);

do $$
begin
  assert (select count(*) from public.entries) = 1, 'A debería ver su movimiento';
  assert (select user_id from public.entries where id = 'e1') = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'user_id debería ser el de A (default auth.uid())';
end $$;

-- LWW: un cambio más viejo no pisa; uno más nuevo sí y mueve server_updated_at.
do $$
declare
  before_ts timestamptz;
begin
  select server_updated_at into before_ts from public.entries where id = 'e1';
  update public.entries set amount_cents = 1, updated_at = 999 where id = 'e1';
  assert (select amount_cents from public.entries where id = 'e1') = 1250, 'LWW: el cambio viejo no debería aplicarse';
  update public.entries set amount_cents = 1, updated_at = 1000 where id = 'e1';
  assert (select amount_cents from public.entries where id = 'e1') = 1250, 'LWW: el mismo updated_at (reintento) no debería aplicarse';
  update public.entries set amount_cents = 2000, updated_at = 2000 where id = 'e1';
  assert (select amount_cents from public.entries where id = 'e1') = 2000, 'LWW: el cambio nuevo debería aplicarse';
  assert (select server_updated_at from public.entries where id = 'e1') > before_ts,
    'server_updated_at debería avanzar';
end $$;

-- A no puede regalarle una fila a B (el trigger mantiene el user_id).
do $$
begin
  update public.entries set user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', updated_at = 3000 where id = 'e1';
  assert (select user_id from public.entries where id = 'e1') = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'user_id no debería cambiar';
end $$;

-- ---------------------------------------------------------------- Usuario B
reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  n integer;
begin
  assert (select count(*) from public.entries) = 0, 'B no debería ver movimientos de A';
  assert (select count(*) from public.categories) = 0, 'B no debería ver categorías de A';
  assert (select count(*) from public.sources) = 0, 'B no debería ver fuentes de A';
  assert (select count(*) from public.budgets) = 0, 'B no debería ver techos de A';
  assert (select count(*) from public.settings) = 0, 'B no debería ver ajustes de A';

  update public.entries set amount_cents = 1, updated_at = 9999 where id = 'e1';
  get diagnostics n = row_count;
  assert n = 0, 'B no debería poder modificar filas de A';

  delete from public.entries where id = 'e1';
  get diagnostics n = row_count;
  assert n = 0, 'B no debería poder borrar filas de A';

  -- Insertar a nombre de A: RLS lo rechaza.
  begin
    insert into public.entries (user_id, id, kind, amount_cents, occurred_on, category_id, created_at, updated_at)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'falsa', 'expense', 1, '2026-10-08', 'comida', 1, 1);
    assert false, 'B no debería poder insertar a nombre de A';
  exception when insufficient_privilege then
    null; -- 42501: rechazado por RLS, como se espera
  end;

  -- Usar la categoría de A desde una fila propia: la FK compuesta lo rechaza.
  begin
    insert into public.entries (id, kind, amount_cents, occurred_on, category_id, created_at, updated_at)
      values ('e-b', 'expense', 1, '2026-10-08', 'comida', 1, 1);
    assert false, 'B no debería poder usar la categoría de A';
  exception when foreign_key_violation then
    null; -- 23503
  end;

  -- delete_account no existe para nadie más que quien llama: B sin filas, nada que verificar aquí.
end $$;

-- ---------------------------------------------------------------- Sin sesión
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
begin
  begin
    perform 1 from public.entries;
    assert false, 'anon no debería poder leer entries';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.delete_account();
    assert false, 'anon no debería poder llamar a delete_account';
  exception when insufficient_privilege then
    null;
  end;
end $$;

reset role;
select 'RLS OK' as resultado;

rollback;
