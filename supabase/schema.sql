-- =====================================================================
-- SaldoClaro - Esquema de base de datos para Supabase (PostgreSQL)
-- Ejecutar en el SQL Editor de tu proyecto Supabase.
-- =====================================================================

-- ---------------------------------------------------------------------
-- EXTENSIONES
-- ---------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. TABLA: profiles
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
    id          uuid primary key references auth.users (id) on delete cascade,
    email       text not null,
    full_name   text,
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. TABLA: accounts
-- ---------------------------------------------------------------------
create table if not exists public.accounts (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    name        text not null, -- 'Yape' | 'BCP' | 'Agora' | 'Lemon' | ...
    balance     numeric(14, 2) not null default 0,
    bank        text,          -- banco/app al que pertenece (libre)
    icon        text,          -- icono Material
    color_hex   text default '444A55', -- color en hex sin '#'
    sort_order  int  not null default 0,
    created_at  timestamptz not null default now(),
    unique (user_id, name)
);

create index if not exists idx_accounts_user_order
    on public.accounts (user_id, sort_order);

-- ---------------------------------------------------------------------
-- 3. TABLA: categories
-- ---------------------------------------------------------------------
create table if not exists public.categories (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    name        text not null,
    type        text not null check (type in ('EXPENSE', 'INCOME')),
    icon        text,
    color_hex   text default '8E44AD',
    keywords    text[] not null default '{}'::text[],
    created_at  timestamptz not null default now(),
    unique (user_id, name)
);

-- ---------------------------------------------------------------------
-- 3.b. TABLA: account_sources (reconocimiento de apps -> cuentas)
-- ---------------------------------------------------------------------
create table if not exists public.account_sources (
    id           uuid primary key default uuid_generate_v4(),
    user_id      uuid not null references auth.users (id) on delete cascade,
    account_id   uuid not null references public.accounts (id) on delete cascade,
    package_name text not null,
    app_name     text,
    created_at   timestamptz not null default now(),
    unique (user_id, package_name)
);

create index if not exists idx_account_sources_account
    on public.account_sources (account_id);

-- ---------------------------------------------------------------------
-- 4. TABLA: transactions
-- ---------------------------------------------------------------------
create table if not exists public.transactions (
    id                  uuid primary key default uuid_generate_v4(),
    user_id             uuid not null references auth.users (id) on delete cascade,
    account_id          uuid not null references public.accounts (id) on delete cascade,
    category_id         uuid references public.categories (id) on delete set null,
    amount              numeric(14, 2) not null check (amount > 0),
    type                text not null check (type in ('EXPENSE', 'INCOME')),
    raw_text            text,
    merchant_or_person  text,
    source_app          text, -- nombre de la app: Yape, BCP, Agora, Lemon
    source              text not null default 'manual' check (source in ('auto', 'manual')),
    created_at          timestamptz not null default now()
);

create index if not exists idx_transactions_user_time
    on public.transactions (user_id, created_at desc);

create index if not exists idx_transactions_account
    on public.transactions (account_id);

-- ---------------------------------------------------------------------
-- TRIGGER: crear profile al registrar un usuario
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
    insert into public.profiles (id, email, full_name)
    values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- TRIGGER: actualizar created_at automáticamente
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

alter table public.profiles     add column if not exists updated_at timestamptz;
alter table public.accounts     add column if not exists updated_at timestamptz;
alter table public.categories   add column if not exists updated_at timestamptz;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

drop trigger if exists set_accounts_updated_at on public.accounts;
create trigger set_accounts_updated_at
    before update on public.accounts
    for each row execute function public.set_updated_at();

drop trigger if exists set_categories_updated_at on public.categories;
create trigger set_categories_updated_at
    before update on public.categories
    for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- RPC: insertar transacción y ajustar el balance de forma atómica.
-- Este es el método preferido por la app (TransactionRepository).
-- ---------------------------------------------------------------------
create or replace function public.insert_transaction(
    p_id            uuid,
    p_user_id       uuid,
    p_account_id    uuid,
    p_category_id   uuid,
    p_amount        numeric,
    p_type          text,
    p_raw_text      text,
    p_merchant_or_person text,
    p_source_app    text,
    p_source        text,
    p_created_at    timestamptz
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    -- Inserta la transacción.
    insert into public.transactions (
        id, user_id, account_id, category_id, amount, type,
        raw_text, merchant_or_person, source_app, source, created_at
    ) values (
        p_id, p_user_id, p_account_id, p_category_id, p_amount, p_type,
        p_raw_text, p_merchant_or_person, p_source_app, p_source, p_created_at
    );

    -- Ajusta el balance de la cuenta (ingreso suma, gasto resta).
    update public.accounts
    set balance = balance + case when p_type = 'INCOME' then p_amount else -p_amount end,
        updated_at = now()
    where id = p_account_id;
end;
$$;

-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.accounts     enable row level security;
alter table public.categories   enable row level security;
alter table public.transactions enable row level security;
alter table public.account_sources enable row level security;

-- profiles: cada usuario solo ve su perfil
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles
    for select using (auth.uid() = id);

drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles
    for update using (auth.uid() = id);

drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles
    for insert with check (auth.uid() = id);

-- accounts
drop policy if exists "accounts_select" on public.accounts;
create policy "accounts_select" on public.accounts
    for select using (auth.uid() = user_id);

drop policy if exists "accounts_insert" on public.accounts;
create policy "accounts_insert" on public.accounts
    for insert with check (auth.uid() = user_id);

drop policy if exists "accounts_update" on public.accounts;
create policy "accounts_update" on public.accounts
    for update using (auth.uid() = user_id);

drop policy if exists "accounts_delete" on public.accounts;
create policy "accounts_delete" on public.accounts
    for delete using (auth.uid() = user_id);

-- categories
drop policy if exists "categories_select" on public.categories;
create policy "categories_select" on public.categories
    for select using (auth.uid() = user_id);

drop policy if exists "categories_insert" on public.categories;
create policy "categories_insert" on public.categories
    for insert with check (auth.uid() = user_id);

drop policy if exists "categories_update" on public.categories;
create policy "categories_update" on public.categories
    for update using (auth.uid() = user_id);

drop policy if exists "categories_delete" on public.categories;
create policy "categories_delete" on public.categories
    for delete using (auth.uid() = user_id);

-- transactions
drop policy if exists "transactions_select" on public.transactions;
create policy "transactions_select" on public.transactions
    for select using (auth.uid() = user_id);

drop policy if exists "transactions_insert" on public.transactions;
create policy "transactions_insert" on public.transactions
    for insert with check (auth.uid() = user_id);

drop policy if exists "transactions_update" on public.transactions;
create policy "transactions_update" on public.transactions
    for update using (auth.uid() = user_id);

drop policy if exists "transactions_delete" on public.transactions;
create policy "transactions_delete" on public.transactions
    for delete using (auth.uid() = user_id);

-- account_sources
drop policy if exists "account_sources_select" on public.account_sources;
create policy "account_sources_select" on public.account_sources
    for select using (auth.uid() = user_id);

drop policy if exists "account_sources_insert" on public.account_sources;
create policy "account_sources_insert" on public.account_sources
    for insert with check (auth.uid() = user_id);

drop policy if exists "account_sources_update" on public.account_sources;
create policy "account_sources_update" on public.account_sources
    for update using (auth.uid() = user_id);

drop policy if exists "account_sources_delete" on public.account_sources;
create policy "account_sources_delete" on public.account_sources
    for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- GRANT (role anon/authenticated)
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant all on public.profiles, public.accounts, public.categories, public.transactions, public.account_sources
    to anon, authenticated;
grant execute on function public.insert_transaction to authenticated;
