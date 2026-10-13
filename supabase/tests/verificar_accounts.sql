-- =============================================================================
-- Verificación de accounts y transfers (Fase 4A) · SOLO en saldoclaro-test
-- =============================================================================
-- Requiere la migración 20261013000100_accounts_transfers.sql aplicada.
-- Cómo correrlo:
--   1. Usa los mismos dos usuarios de verificar_rls.sql (o crea dos nuevos con
--      Authentication → Users → Add user, "Auto Confirm User"). Reemplaza:
--        aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa  →  UUID del usuario A
--        bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb  →  UUID del usuario B
--   2. Pega todo en el SQL editor y ejecuta.
-- Resultado esperado: una última fila "accounts OK". Si algo falla, el editor
-- muestra el ASSERT que falló y su mensaje.
-- Termina en ROLLBACK: no queda nada (tampoco el borrado de A del final).
-- =============================================================================

begin;

-- ---------------------------------------------------------------- Usuario A
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

insert into public.categories (id, name, icon, color_hex, sort_order, is_default, updated_at)
  values ('comida', 'Comida', 'restaurant', 'cat:1', 0, true, 1000);
insert into public.accounts (id, name, icon, color_hex, sort_order, created_at, opening_balance_cents, opening_balance_at, updated_at)
  values ('yape', 'Yape', 'phone', '#525252', 0, 1000, 50000, 1000, 1000);
insert into public.accounts (id, name, icon, color_hex, sort_order, created_at, updated_at)
  values ('efectivo', 'Efectivo', 'wallet', '#525252', 1, 1000, 1000);
insert into public.entries (id, kind, amount_cents, occurred_on, category_id, account_id, created_at, updated_at)
  values ('e1', 'expense', 1250, '2026-10-08', 'comida', 'yape', 1000, 1000);
insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
  values ('t1', 'yape', 'efectivo', 2000, '2026-10-09', 1000, 1000);
-- Un lado "Sin asignar" (nulo) es válido (D3).
insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
  values ('t2', null, 'efectivo', 500, '2026-10-09', 1000, 1000);

do $$
begin
  assert (select count(*) from public.accounts) = 2, 'A debería ver sus 2 cuentas';
  assert (select count(*) from public.transfers) = 2, 'A debería ver sus 2 transferencias';
  assert (select user_id from public.accounts where id = 'yape') = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'user_id de la cuenta debería ser el de A (default auth.uid())';
  assert (select server_updated_at from public.transfers where id = 't1') is not null,
    'el trigger debería poner server_updated_at';
end $$;

-- LWW en las tablas nuevas (el trigger de 003).
do $$
begin
  update public.accounts set name = 'Viejo', updated_at = 999 where id = 'yape';
  assert (select name from public.accounts where id = 'yape') = 'Yape', 'LWW accounts: el cambio viejo no se aplica';
  update public.accounts set name = 'Yape BCP', updated_at = 2000 where id = 'yape';
  assert (select name from public.accounts where id = 'yape') = 'Yape BCP', 'LWW accounts: el cambio nuevo se aplica';
  update public.transfers set amount_cents = 1, updated_at = 1000 where id = 't1';
  assert (select amount_cents from public.transfers where id = 't1') = 2000, 'LWW transfers: el reintento no se aplica';
end $$;

-- CHECKs.
do $$
begin
  begin
    insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
      values ('mal1', 'yape', 'yape', 100, '2026-10-09', 1, 1);
    assert false, 'una transferencia a la misma cuenta debería fallar';
  exception when check_violation then null;
  end;
  begin
    insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
      values ('mal2', null, null, 100, '2026-10-09', 1, 1);
    assert false, 'una transferencia sin ningún lado debería fallar';
  exception when check_violation then null;
  end;
  begin
    insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
      values ('mal3', 'yape', 'efectivo', 0, '2026-10-09', 1, 1);
    assert false, 'monto 0 debería fallar';
  exception when check_violation then null;
  end;
  begin
    insert into public.accounts (id, name, icon, color_hex, sort_order, created_at, opening_balance_cents, updated_at)
      values ('mal4', 'Mal', 'x', '#525252', 9, 1, 100, 1);
    assert false, 'un saldo inicial sin su instante debería fallar';
  exception when check_violation then null;
  end;
  begin
    insert into public.entries (id, kind, amount_cents, occurred_on, category_id, account_id, created_at, updated_at)
      values ('mal5', 'expense', 1, '2026-10-08', 'comida', 'no-existe', 1, 1);
    assert false, 'un movimiento con una cuenta que no existe debería fallar';
  exception when foreign_key_violation then null;
  end;
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
  assert (select count(*) from public.accounts) = 0, 'B no debería ver cuentas de A';
  assert (select count(*) from public.transfers) = 0, 'B no debería ver transferencias de A';

  update public.accounts set name = 'Hack', updated_at = 9999 where id = 'yape';
  get diagnostics n = row_count;
  assert n = 0, 'B no debería poder modificar cuentas de A';

  delete from public.transfers where id = 't1';
  get diagnostics n = row_count;
  assert n = 0, 'B no debería poder borrar transferencias de A';

  begin
    insert into public.accounts (user_id, id, name, icon, color_hex, sort_order, created_at, updated_at)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'falsa', 'Falsa', 'x', '#525252', 0, 1, 1);
    assert false, 'B no debería poder crear cuentas a nombre de A';
  exception when insufficient_privilege then null;
  end;

  -- Usar la cuenta de A desde filas propias: la FK compuesta lo rechaza.
  insert into public.categories (id, name, icon, color_hex, sort_order, updated_at)
    values ('comida', 'Comida', 'restaurant', 'cat:1', 0, 1);
  begin
    insert into public.entries (id, kind, amount_cents, occurred_on, category_id, account_id, created_at, updated_at)
      values ('e-b', 'expense', 1, '2026-10-08', 'comida', 'yape', 1, 1);
    assert false, 'B no debería poder usar la cuenta de A en un movimiento';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.transfers (id, from_account_id, to_account_id, amount_cents, occurred_on, created_at, updated_at)
      values ('t-b', 'yape', null, 1, '2026-10-08', 1, 1);
    assert false, 'B no debería poder usar la cuenta de A en una transferencia';
  exception when foreign_key_violation then null;
  end;
end $$;

-- ---------------------------------------------------------------- Sin sesión
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
begin
  begin
    perform 1 from public.accounts;
    assert false, 'anon no debería poder leer accounts';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.transfers;
    assert false, 'anon no debería poder leer transfers';
  exception when insufficient_privilege then null;
  end;
end $$;

-- -------------------------------------------- delete_account borra lo nuevo
reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;
select public.delete_account();

reset role;
do $$
begin
  assert not exists (select 1 from public.accounts where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'las cuentas de A deberían haberse borrado';
  assert not exists (select 1 from public.transfers where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'las transferencias de A deberían haberse borrado';
  assert not exists (select 1 from public.entries where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'los movimientos de A deberían haberse borrado';
  assert exists (select 1 from public.categories where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    'los datos de B NO deberían verse afectados';
end $$;

select 'accounts OK' as resultado;

rollback;
