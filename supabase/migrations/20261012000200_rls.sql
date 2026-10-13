-- =============================================================================
-- 002 · Row Level Security: cada usuario solo ve y toca sus filas
-- =============================================================================
-- La anon key viaja dentro del APK (es pública por diseño): la seguridad real
-- está aquí. Reglas:
--   · RLS activo en las 5 tablas. Sin política = sin acceso.
--   · Solo el rol `authenticated` (usuario con sesión). `anon` (sin sesión)
--     no tiene ni permisos de tabla: ni siquiera llega a evaluar RLS.
--   · 4 políticas por tabla, nombradas <tabla>_<operación>_own.
--   · (select auth.uid()) en vez de auth.uid(): Postgres lo evalúa una vez
--     por consulta y no una vez por fila (recomendación de Supabase).
--   · update lleva USING (qué filas puedo tocar) y WITH CHECK (cómo pueden
--     quedar): nadie puede pasarse una fila a otro usuario.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Permisos de tabla: nada para anon; solo DML para authenticated.
-- (Supabase da por defecto todos los permisos a anon y authenticated en las
-- tablas nuevas de public; aquí se restringen.)
-- -----------------------------------------------------------------------------
revoke all on table public.categories, public.sources, public.entries, public.budgets, public.settings
  from anon, authenticated;
grant select, insert, update, delete
  on table public.categories, public.sources, public.entries, public.budgets, public.settings
  to authenticated;

alter table public.categories enable row level security;
alter table public.sources    enable row level security;
alter table public.entries    enable row level security;
alter table public.budgets    enable row level security;
alter table public.settings   enable row level security;

-- -----------------------------------------------------------------------------
-- categories
-- -----------------------------------------------------------------------------
create policy categories_select_own on public.categories
  for select to authenticated using ((select auth.uid()) = user_id);
create policy categories_insert_own on public.categories
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy categories_update_own on public.categories
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy categories_delete_own on public.categories
  for delete to authenticated using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- sources
-- -----------------------------------------------------------------------------
create policy sources_select_own on public.sources
  for select to authenticated using ((select auth.uid()) = user_id);
create policy sources_insert_own on public.sources
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy sources_update_own on public.sources
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy sources_delete_own on public.sources
  for delete to authenticated using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- entries
-- -----------------------------------------------------------------------------
create policy entries_select_own on public.entries
  for select to authenticated using ((select auth.uid()) = user_id);
create policy entries_insert_own on public.entries
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy entries_update_own on public.entries
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy entries_delete_own on public.entries
  for delete to authenticated using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- budgets
-- -----------------------------------------------------------------------------
create policy budgets_select_own on public.budgets
  for select to authenticated using ((select auth.uid()) = user_id);
create policy budgets_insert_own on public.budgets
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy budgets_update_own on public.budgets
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy budgets_delete_own on public.budgets
  for delete to authenticated using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- settings
-- -----------------------------------------------------------------------------
create policy settings_select_own on public.settings
  for select to authenticated using ((select auth.uid()) = user_id);
create policy settings_insert_own on public.settings
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy settings_update_own on public.settings
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy settings_delete_own on public.settings
  for delete to authenticated using ((select auth.uid()) = user_id);

commit;
