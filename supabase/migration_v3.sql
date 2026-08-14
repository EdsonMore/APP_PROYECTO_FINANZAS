-- =====================================================================
-- SaldoClaro - Migración v3 (Ecosistema financiero inteligente)
-- Ejecutar en el SQL Editor de tu proyecto Supabase DESPUÉS de schema.sql
-- y migration_v2.sql. Es 100% idempotente (se puede re-ejecutar).
--
-- 1. transactions.transaction_type ('INCOME'|'EXPENSE') derivada de `type`
-- 2. RPC insert_transaction: suma al saldo si es 'INCOME', resta si 'EXPENSE'
-- 3. Tabla auxiliar `splits` (deudas/cuenta por cobrar a la pareja) + RLS
-- 4. profiles.monthly_budget y categories.budget (presupuestos)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TRANSACTIONS: campo `transaction_type` ('INCOME'|'EXPENSE')
-- Mantiene `type` como fuente de verdad y expone `transaction_type` como
-- columna generada en MAYÚSCULAS para consultas/consistencia de la app.
-- ---------------------------------------------------------------------
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name   = 'transactions'
          and column_name  = 'transaction_type'
    ) then
        alter table public.transactions
            add column transaction_type text
                generated always as (upper(type)) stored;
    end if;
end $$;

create index if not exists idx_transactions_type
    on public.transactions (transaction_type);

-- ---------------------------------------------------------------------
-- 2. RPC: insert_transaction (atómico: registrar + ajustar saldo)
-- Si p_type es 'INCOME' (o 'income') SUMA al balance; si es 'EXPENSE'
-- ('expense') RESTA. Recrea la función por si la anterior existía.
-- ---------------------------------------------------------------------
create or replace function public.insert_transaction(
    p_id                 uuid,
    p_user_id            uuid,
    p_account_id         uuid,
    p_category_id        uuid,
    p_amount             numeric,
    p_type               text,
    p_raw_text           text,
    p_merchant_or_person text,
    p_source_app         text,
    p_source             text,
    p_created_at         timestamptz
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_type text := upper(p_type);
begin
    if v_type not in ('INCOME', 'EXPENSE') then
        raise exception 'Tipo de transacción inválido: %', p_type;
    end if;

    -- Inserta la transacción.
    insert into public.transactions (
        id, user_id, account_id, category_id, amount, type,
        raw_text, merchant_or_person, source_app, source, created_at
    ) values (
        p_id, p_user_id, p_account_id, p_category_id, p_amount, v_type,
        p_raw_text, p_merchant_or_person, p_source_app, p_source, p_created_at
    );

    -- Ajusta el balance: INGRESO suma, GASTO resta.
    update public.accounts
    set balance = balance + case when v_type = 'INCOME' then p_amount else -p_amount end,
        updated_at = now()
    where id = p_account_id;
end;
$$;

grant execute on function public.insert_transaction to authenticated;

-- ---------------------------------------------------------------------
-- 2.b. RPC utilitaria: ajustar saldo manualmente (histórico / splits)
-- ---------------------------------------------------------------------
create or replace function public.adjust_account_balance(
    p_account_id uuid,
    p_delta      numeric
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.accounts
    set balance = balance + p_delta,
        updated_at = now()
    where id = p_account_id;
end;
$$;

grant execute on function public.adjust_account_balance to authenticated;

-- ---------------------------------------------------------------------
-- 3. TABLA: splits (deudas / cuentas por cobrar a la pareja)
-- Cuando el usuario paga una cena de S/ 100 y decide cobrar el 50% a su
-- pareja, se registra una fila aquí (transaction_id, debtor_name, amount).
-- ---------------------------------------------------------------------
create table if not exists public.splits (
    id             uuid primary key default uuid_generate_v4(),
    user_id        uuid not null references auth.users (id) on delete cascade,
    transaction_id uuid not null references public.transactions (id) on delete cascade,
    debtor_name    text not null,        -- 'Mi pareja', 'Carmen', ...
    amount         numeric(14, 2) not null check (amount > 0),
    is_paid        boolean not null default false,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz
);

create index if not exists idx_splits_user_paid
    on public.splits (user_id, is_paid, created_at desc);

create index if not exists idx_splits_transaction
    on public.splits (transaction_id);

-- Trigger para actualizar updated_at en splits.
drop trigger if exists set_splits_updated_at on public.splits;
create trigger set_splits_updated_at
    before update on public.splits
    for each row execute function public.set_updated_at();

-- Row Level Security para splits
alter table public.splits enable row level security;

drop policy if exists "splits_select" on public.splits;
create policy "splits_select" on public.splits
    for select using (auth.uid() = user_id);

drop policy if exists "splits_insert" on public.splits;
create policy "splits_insert" on public.splits
    for insert with check (auth.uid() = user_id);

drop policy if exists "splits_update" on public.splits;
create policy "splits_update" on public.splits
    for update using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "splits_delete" on public.splits;
create policy "splits_delete" on public.splits
    for delete using (auth.uid() = user_id);

grant all on public.splits to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. PRESUPUESTOS
-- 4.a. profiles.monthly_budget: presupuesto mensual global (alerta de
--      ritmo de gasto: 70% antes de la mitad del mes).
-- 4.b. categories.budget: presupuesto por categoría (p. ej. "Enamorada /
--      Pareja") usado por el módulo "Especial Pareja".
-- ---------------------------------------------------------------------
alter table public.profiles
    add column if not exists monthly_budget numeric(14, 2);

alter table public.categories
    add column if not exists budget numeric(14, 2);

-- ---------------------------------------------------------------------
-- GRANTS finales
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant all on public.profiles, public.transactions, public.splits
    to anon, authenticated;