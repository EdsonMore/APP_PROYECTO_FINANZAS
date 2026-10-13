-- =============================================================================
-- 005 · Multi-cuenta (Fase 4A): accounts, transfers y entries.account_id con FK
-- =============================================================================
-- Mismas reglas que 001-003 (ver sus encabezados): user_id con default
-- auth.uid() y on delete cascade, PK (user_id, id), updated_at del teléfono
-- (last-write-wins), server_updated_at del servidor, deleted_at = lápida.
--
--   · accounts: espejo de categories + created_at y el saldo inicial de la
--     cuenta (los dos campos juntos o ninguno). Las cuentas se archivan, no se
--     borran; deleted_at queda por uniformidad con el resto del sync.
--   · transfers: tabla aparte (D1 de la 4A), NO un kind de entries: así no
--     cuentan como gasto ni ingreso en ninguna fórmula. Un lado nulo es
--     "Sin asignar" (D3); nunca los dos, nunca la misma cuenta en los dos.
--   · entries.account_id: FK compuesta hacia accounts (D2; reemplaza la A5).
--     Hasta hoy todos los account_id son NULL, así que la FK valida sin datos
--     que revisar. Con account_id NULL la FK no se evalúa.
--   · Las FK entre tablas de un mismo usuario son NO ACTION: al borrar el
--     usuario (delete_account) el cascade borra todo en la misma sentencia y
--     la verificación de la FK pasa al final (ver verificar_accounts.sql).
--
-- Deshacer (solo si todavía no hay datos de cuentas en el servidor):
--   begin;
--   alter table public.entries drop constraint entries_account_fk;
--   drop table public.transfers;
--   drop table public.accounts;
--   drop index if exists public.entries_account_idx;
--   commit;
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- accounts: Yape, BCP, efectivo… (las crea el usuario; sin semilla)
-- -----------------------------------------------------------------------------
create table public.accounts (
  user_id               uuid        not null default auth.uid()
                                    references auth.users (id) on delete cascade,
  id                    text        not null check (char_length(id) between 1 and 64),
  name                  text        not null check (char_length(name) between 1 and 20),
  icon                  text        not null check (char_length(icon) between 1 and 64),
  color_hex             text        not null check (char_length(color_hex) between 1 and 16),
  sort_order            integer     not null,
  archived              boolean     not null default false,
  is_default            boolean     not null default false,
  created_at            bigint      not null check (created_at > 0),
  opening_balance_cents bigint,
  opening_balance_at    bigint      check (opening_balance_at > 0),
  updated_at            bigint      not null check (updated_at > 0),
  server_updated_at     timestamptz not null default now(),
  deleted_at            bigint      check (deleted_at > 0),
  primary key (user_id, id),
  constraint accounts_opening_pair check ((opening_balance_cents is null) = (opening_balance_at is null))
);

-- -----------------------------------------------------------------------------
-- transfers: plata que pasa de una cuenta a otra. No es gasto ni ingreso.
-- -----------------------------------------------------------------------------
create table public.transfers (
  user_id           uuid        not null default auth.uid()
                                references auth.users (id) on delete cascade,
  id                text        not null check (char_length(id) between 1 and 64),
  from_account_id   text,
  to_account_id     text,
  amount_cents      bigint      not null check (amount_cents > 0),
  occurred_on       date        not null,
  note              text        check (char_length(note) <= 1000),
  created_at        bigint      not null check (created_at > 0),
  updated_at        bigint      not null check (updated_at > 0),
  server_updated_at timestamptz not null default now(),
  deleted_at        bigint      check (deleted_at > 0),
  primary key (user_id, id),
  constraint transfers_one_side check (from_account_id is not null or to_account_id is not null),
  constraint transfers_distinct check (from_account_id is distinct from to_account_id),
  constraint transfers_from_fk foreign key (user_id, from_account_id)
    references public.accounts (user_id, id),
  constraint transfers_to_fk foreign key (user_id, to_account_id)
    references public.accounts (user_id, id)
);

-- -----------------------------------------------------------------------------
-- entries.account_id → accounts (misma cuenta del MISMO usuario)
-- -----------------------------------------------------------------------------
alter table public.entries
  add constraint entries_account_fk foreign key (user_id, account_id)
    references public.accounts (user_id, id);

-- -----------------------------------------------------------------------------
-- Índices: bajar cambios y verificar las FK compuestas
-- -----------------------------------------------------------------------------
create index accounts_pull_idx  on public.accounts  (user_id, server_updated_at);
create index transfers_pull_idx on public.transfers (user_id, server_updated_at);
create index entries_account_idx  on public.entries   (user_id, account_id)      where account_id is not null;
create index transfers_from_idx   on public.transfers (user_id, from_account_id) where from_account_id is not null;
create index transfers_to_idx     on public.transfers (user_id, to_account_id)   where to_account_id is not null;

-- -----------------------------------------------------------------------------
-- RLS (mismo patrón que 002): nada para anon, 4 políticas por tabla
-- -----------------------------------------------------------------------------
revoke all on table public.accounts, public.transfers from anon, authenticated;
grant select, insert, update, delete on table public.accounts, public.transfers to authenticated;

alter table public.accounts  enable row level security;
alter table public.transfers enable row level security;

create policy accounts_select_own on public.accounts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy accounts_insert_own on public.accounts
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy accounts_update_own on public.accounts
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy accounts_delete_own on public.accounts
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy transfers_select_own on public.transfers
  for select to authenticated using ((select auth.uid()) = user_id);
create policy transfers_insert_own on public.transfers
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy transfers_update_own on public.transfers
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy transfers_delete_own on public.transfers
  for delete to authenticated using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- Trigger de sync (la misma función de 003)
-- -----------------------------------------------------------------------------
create trigger accounts_sync_before_write
  before insert or update on public.accounts
  for each row execute function public.sync_before_write();
create trigger transfers_sync_before_write
  before insert or update on public.transfers
  for each row execute function public.sync_before_write();

commit;
