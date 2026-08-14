-- =====================================================================
-- SaldoClaro - Migración v4 (Ciclos de Facturación y Servicios)
-- Ejecutar en el SQL Editor de tu proyecto Supabase DESPUÉS de schema.sql,
-- migration_v2.sql y migration_v3.sql. Es 100% idempotente.
--
-- 1. Tabla `billing_cycles`: servicios recurrentes (luz, agua, internet,
--    streaming, EPS, etc.) con frecuencia, keywords para Auto-Match y
--    estados (pending / paid / overdue).
-- 2. RLS: cada usuario solo ve/edita sus propios ciclos.
-- 3. Índice por usuario/fecha de vencimiento + trigger de updated_at.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLA: billing_cycles
-- ---------------------------------------------------------------------
create table if not exists public.billing_cycles (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references public.profiles (id) on delete cascade,
    title       text not null,               -- Ej: "ENOSA - Luz", "EPS Grau", "Netflix"
    category    text not null check (category in ('utility_service', 'subscription')),
    amount      numeric(10, 2) not null default 0.00,
    due_date    date not null,               -- Próxima fecha de vencimiento
    frequency   text not null check (frequency in ('monthly', 'bimonthly', 'yearly')),
    supply_number text,                      -- Código de cliente/suministro (opcional)
    keywords    text[] not null default '{}', -- Ej: ['enosa', 'luz', 'eps grau', 'netflix']
    is_auto_pay boolean not null default false,
    is_active   boolean not null default true, -- Pausar/reanudar sin borrar
    status      text not null default 'pending' check (status in ('pending', 'paid', 'overdue')),
    created_at  timestamptz not null default timezone('utc'::text, now()),
    updated_at  timestamptz not null default timezone('utc'::text, now())
);

create index if not exists idx_billing_cycles_user_due
    on public.billing_cycles (user_id, due_date);

create index if not exists idx_billing_cycles_user_active_status
    on public.billing_cycles (user_id, is_active, status);

-- Trigger para actualizar updated_at en cada UPDATE.
drop trigger if exists set_billing_cycles_updated_at on public.billing_cycles;
create trigger set_billing_cycles_updated_at
    before update on public.billing_cycles
    for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table public.billing_cycles enable row level security;

drop policy if exists "billing_cycles_select" on public.billing_cycles;
create policy "billing_cycles_select" on public.billing_cycles
    for select using (auth.uid() = user_id);

drop policy if exists "billing_cycles_insert" on public.billing_cycles;
create policy "billing_cycles_insert" on public.billing_cycles
    for insert with check (auth.uid() = user_id);

drop policy if exists "billing_cycles_update" on public.billing_cycles;
create policy "billing_cycles_update" on public.billing_cycles
    for update using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "billing_cycles_delete" on public.billing_cycles;
create policy "billing_cycles_delete" on public.billing_cycles
    for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- 3. GRANTS
-- ---------------------------------------------------------------------
grant all on public.billing_cycles to anon, authenticated;
