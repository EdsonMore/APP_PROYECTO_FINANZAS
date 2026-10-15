-- =============================================================================
-- Verificación de ai_usage (5C-Infra) · SOLO en saldoclaro-test
-- =============================================================================
-- Cómo correrlo:
--   1. Aplica supabase/migrations/20261015000100_ai_usage.sql.
--   2. En saldoclaro-test crea dos usuarios de prueba A y B (Add user, Auto
--      Confirm). Reemplaza:
--        aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa  →  UUID de A
--        bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb  →  UUID de B
--   3. Ejecuta todo en el SQL editor.
-- Resultado esperado: "ai_usage OK". Termina en ROLLBACK: no deja nada.
-- =============================================================================

begin;

-- Día de Lima: 04:30 UTC del 15 es todavía el 14 en Lima; 05:30 UTC ya es el 15.
do $$
begin
  assert public.ai_day('2026-10-15 04:30+00') = date '2026-10-14', 'ai_day: 23:30 de Lima es el día 14';
  assert public.ai_day('2026-10-15 05:30+00') = date '2026-10-15', 'ai_day: 00:30 de Lima ya es el día 15';
end $$;

-- A consulta 3 veces.
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  assert public.ai_usage_today() = 0, 'A empieza en 0';
  assert public.ai_record_use() = 1, 'primera consulta: 1';
  assert public.ai_record_use() = 2, 'segunda consulta: 2';
  assert public.ai_record_use() = 3, 'tercera consulta: 3';
  assert public.ai_usage_today() = 3, 'A ve 3';
end $$;

-- A no puede escribir directo (ni bajarse el contador).
do $$
begin
  begin
    update public.ai_usage set count = 0;
    assert false, 'A no debería poder hacer update';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.ai_usage (user_id, day, count)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.ai_day(), 0);
    assert false, 'A no debería poder hacer insert';
  exception when insufficient_privilege then null;
  end;
end $$;

-- B no ve el uso de A y empieza en 0.
reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.ai_usage) = 0, 'B no debería ver filas de A';
  assert public.ai_usage_today() = 0, 'B empieza en 0';
end $$;

-- Sin sesión, ai_record_use falla.
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  begin
    perform public.ai_record_use();
    assert false, 'ai_record_use sin sub debería fallar';
  exception when sqlstate '28000' then null;
  end;
end $$;

-- Borrar a A borra su uso (cascade).
reset role;
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$
begin
  assert not exists (select 1 from public.ai_usage where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'el uso de A debería borrarse con su cuenta';
end $$;

select 'ai_usage OK' as resultado;

rollback;
