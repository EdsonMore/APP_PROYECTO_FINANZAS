-- =====================================================================
-- SaldoClaro - Migración v2 (Funcionalidades de valor agregado)
-- Ejecutar en el SQL Editor de tu proyecto Supabase DESPUÉS de schema.sql
-- (o aplicar las partes que falten si ya tenías el esquema base).
--
-- 1. Campos dinámicos para cuentas (bank, icon, color_hex, sort_order)
-- 2. Campos para categorías (color_hex, keywords) + RLS
-- 3. Tabla account_sources (mapeo de packages de apps -> cuentas)
-- =====================================================================

-- ---------------------------------------------------------------------
-- ACCOUNTS: campos dinámicos
-- ---------------------------------------------------------------------
alter table public.accounts
    add column if not exists bank       text,
    add column if not exists icon       text,
    add column if not exists color_hex  text default '444A55',
    add column if not exists sort_order int  not null default 0;

create index if not exists idx_accounts_user_order
    on public.accounts (user_id, sort_order);

-- ---------------------------------------------------------------------
-- CATEGORIES: campos para categorización automática
-- ---------------------------------------------------------------------
alter table public.categories
    add column if not exists color_hex text default '8E44AD',
    add column if not exists keywords  text[] not null default '{}'::text[];

create index if not exists idx_categories_user_name
    on public.categories (user_id, name);

-- ---------------------------------------------------------------------
-- TABLA: account_sources
-- Mapea un package de app (ej. "com.interbank.bond") a una cuenta del
-- usuario para el reconocimiento automático de nuevas apps.
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
-- ROW LEVEL SECURITY para account_sources
-- ---------------------------------------------------------------------
alter table public.account_sources enable row level security;

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
-- GRANTS
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant all on public.account_sources to anon, authenticated;
