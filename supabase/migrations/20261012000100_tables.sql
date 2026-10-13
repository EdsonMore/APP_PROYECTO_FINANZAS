-- =============================================================================
-- 001 · Tablas de SaldoClaro (Fase 3A)
-- =============================================================================
-- Espejo de la base local (drift, lib/data/database.dart) más lo que pide la
-- sync. Reglas comunes a todas las tablas:
--   · user_id: dueño de la fila. Por defecto auth.uid(); RLS (002) impide
--     escribir filas de otro. Borrar el usuario borra sus filas (cascade).
--   · Clave primaria compuesta (user_id, id): los ids de la semilla son fijos
--     ('comida', 'chamba'…) y se repiten entre usuarios. Los ids son los
--     mismos del teléfono: no hay remote_id.
--   · updated_at: epoch ms puesto por el TELÉFONO. Decide los conflictos
--     (last-write-wins, ver 003).
--   · server_updated_at: lo pone el trigger (003) con la hora del servidor.
--     Solo sirve para bajar cambios ("lo que cambió desde X").
--   · deleted_at: epoch ms del teléfono al borrar (lápida). La fila no se
--     borra para que los otros teléfonos se enteren.
--   · Dinero en centavos enteros (bigint). Fechas de evento como `date`.
--   · name ≤ 20 como en la app (catalogNameMaxLength; sin emojis, así que
--     caracteres visibles = puntos de código en la práctica).
--   · Sin UNIQUE en `name`: el teléfono ya lo exige; en el servidor haría
--     fallar la sync si dos teléfonos renombran a la vez.
-- Tablas locales que NO se sincronizan en la Fase 3: accounts (vacía hasta
-- la Fase 4) y goals (sin uso).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- categories: categorías de gasto
-- -----------------------------------------------------------------------------
create table public.categories (
  user_id           uuid        not null default auth.uid()
                                references auth.users (id) on delete cascade,
  id                text        not null check (char_length(id) between 1 and 64),
  name              text        not null check (char_length(name) between 1 and 20),
  icon              text        not null check (char_length(icon) between 1 and 64),
  color_hex         text        not null check (char_length(color_hex) between 1 and 16),
  sort_order        integer     not null,
  archived          boolean     not null default false,
  is_default        boolean     not null default false,
  updated_at        bigint      not null check (updated_at > 0),
  server_updated_at timestamptz not null default now(),
  deleted_at        bigint      check (deleted_at > 0),
  primary key (user_id, id)
);

-- -----------------------------------------------------------------------------
-- sources: fuentes de ingreso (mismas columnas que categories)
-- -----------------------------------------------------------------------------
create table public.sources (
  user_id           uuid        not null default auth.uid()
                                references auth.users (id) on delete cascade,
  id                text        not null check (char_length(id) between 1 and 64),
  name              text        not null check (char_length(name) between 1 and 20),
  icon              text        not null check (char_length(icon) between 1 and 64),
  color_hex         text        not null check (char_length(color_hex) between 1 and 16),
  sort_order        integer     not null,
  archived          boolean     not null default false,
  is_default        boolean     not null default false,
  updated_at        bigint      not null check (updated_at > 0),
  server_updated_at timestamptz not null default now(),
  deleted_at        bigint      check (deleted_at > 0),
  primary key (user_id, id)
);

-- -----------------------------------------------------------------------------
-- entries: movimientos. Un gasto lleva categoría; un ingreso, fuente.
-- account_id sin FK: accounts no se sincroniza hasta la Fase 4.
-- -----------------------------------------------------------------------------
create table public.entries (
  user_id           uuid        not null default auth.uid()
                                references auth.users (id) on delete cascade,
  id                text        not null check (char_length(id) between 1 and 64),
  kind              text        not null check (kind in ('income', 'expense')),
  amount_cents      bigint      not null check (amount_cents > 0),
  occurred_on       date        not null,
  category_id       text,
  source_id         text,
  note              text        check (char_length(note) <= 1000),
  origin            text        not null default 'manual' check (origin in ('manual', 'auto')),
  account_label     text        check (char_length(account_label) <= 100),
  account_id        text,
  created_at        bigint      not null check (created_at > 0),
  updated_at        bigint      not null check (updated_at > 0),
  server_updated_at timestamptz not null default now(),
  deleted_at        bigint      check (deleted_at > 0),
  primary key (user_id, id),
  constraint entries_kind_matches_pick check (
    (kind = 'expense' and category_id is not null and source_id is null)
    or (kind = 'income' and source_id is not null and category_id is null)
  ),
  -- La categoría/fuente tiene que ser del MISMO usuario (por eso la FK
  -- incluye user_id). Con category_id nulo la FK no se evalúa.
  constraint entries_category_fk foreign key (user_id, category_id)
    references public.categories (user_id, id),
  constraint entries_source_fk foreign key (user_id, source_id)
    references public.sources (user_id, id)
);

-- -----------------------------------------------------------------------------
-- budgets: techo mensual por categoría
-- -----------------------------------------------------------------------------
create table public.budgets (
  user_id           uuid        not null default auth.uid()
                                references auth.users (id) on delete cascade,
  category_id       text        not null,
  cap_cents         bigint      not null check (cap_cents > 0),
  updated_at        bigint      not null check (updated_at > 0),
  server_updated_at timestamptz not null default now(),
  deleted_at        bigint      check (deleted_at > 0),
  primary key (user_id, category_id),
  constraint budgets_category_fk foreign key (user_id, category_id)
    references public.categories (user_id, id)
);

-- -----------------------------------------------------------------------------
-- settings: una fila por usuario (en el teléfono es la fila id = 1).
-- Sin deleted_at: los ajustes no se borran, solo cambian.
-- -----------------------------------------------------------------------------
create table public.settings (
  user_id               uuid        primary key default auth.uid()
                                    references auth.users (id) on delete cascade,
  mode                  text        not null check (mode in ('stable', 'variable', 'survival')),
  -- La app limita a 30 caracteres VISIBLES (un emoji cuenta 1). Postgres cuenta
  -- puntos de código (un emoji de familia ocupa 7). Este límite solo frena
  -- basura: 400 cubre 30 emojis de familia (210) más texto. Vacío = NULL.
  space_name            text        check (char_length(space_name) between 1 and 400),
  runway_window_days    integer     not null default 14 check (runway_window_days between 7 and 90),
  income_window_days    integer     not null default 30 check (income_window_days in (30, 60, 90)),
  opening_balance_cents bigint,
  opening_balance_at    bigint      check (opening_balance_at > 0),
  onboarding_done       boolean     not null default false,
  updated_at            bigint      not null check (updated_at > 0),
  server_updated_at     timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Índices
-- La clave primaria (user_id, …) ya cubre "las filas de este usuario".
-- Bajar cambios: where user_id = $1 and server_updated_at > $cursor.
-- updated_at no necesita índice: solo se compara fila contra fila (003).
-- -----------------------------------------------------------------------------
create index categories_pull_idx on public.categories (user_id, server_updated_at);
create index sources_pull_idx    on public.sources    (user_id, server_updated_at);
create index entries_pull_idx    on public.entries    (user_id, server_updated_at);
create index budgets_pull_idx    on public.budgets    (user_id, server_updated_at);
create index settings_pull_idx   on public.settings   (user_id, server_updated_at);

-- Para las FK compuestas de entries (verificar y borrar en cascada rápido).
create index entries_category_idx on public.entries (user_id, category_id) where category_id is not null;
create index entries_source_idx   on public.entries (user_id, source_id)   where source_id is not null;

commit;
