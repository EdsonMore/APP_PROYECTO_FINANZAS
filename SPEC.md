# Spec: SaldoClaro (Fase 1 — MVP local-first)

## Objetivo

Microapp de finanzas personales que responde dos preguntas: **"¿en qué se me va
la plata?"** y **"¿me va a alcanzar?"**.

Usuario objetivo: no asumimos ingreso fijo. Puede ser asalariado, freelancer,
estar sin trabajo con entradas puntuales, o tener ingreso mixto.

### Reglas duras de producto

- Funciona desde el día 1 con S/ 0 de ingreso y solo gastos.
- El onboarding **no** pide ingreso mensual, día de pago ni meta de ahorro.
- Una entrada de dinero es **"ingreso"**, nunca "sueldo". No se asume periodicidad.
- Nunca se muestra "presupuesto restante" sin ingreso registrado en el mes (en el Home; ver "Quedan S/ X" en §Modos de uso).
  En su lugar se muestra el gasto del período + runway.
- Registrar gasto e ingreso tiene la misma prioridad: ambos a ≤ 2 toques de
  navegación desde el Home.
- Fase 1: cero red, sin login, sin captura de notificaciones.

## Fases

| Fase | Contenido |
|---|---|
| 1a | Dominio y datos (este documento, drift, `metrics.dart`) |
| 1b | Sistema visual, Onboarding, Home, registro, Ajustes, CSV |
| 1c | Presupuesto, Insights; cierre con code-review y security-review |
| 2 | Cierre del MVP: legal, privacidad, AAB, canal cerrado (20–50 testers) |
| 3 | Sync opcional con Supabase |
| 4 | Captura experimental (`lib/features/capture/README.md`) |
| 5 | Publicación pública en Play Store, después de validar el sync |

## Modos de uso

| Modo (BD) | Opción de onboarding | Énfasis |
|---|---|---|
| `stable` | Estables | Presupuesto mensual por techos vs gasto real |
| `variable` | Variables, **Mixtos** | Ingreso típico 30/60/90, gasto, runway |
| `survival` | Sin ingreso fijo ahora | Runway, semáforo, CTA de ingreso destacado |

- **Mixto → `mode = 'variable'`.** `mixed` no existe en la BD. Es azúcar de UI:
  en el onboarding preselecciona "Chamba" como fuente favorita. Por lo demás se
  comporta igual que Variable. Código: `modeFor(IncomeProfile)`.
- El modo solo cambia cálculos derivados y énfasis. Los datos son los mismos.
- La pestaña Presupuesto existe **solo en `stable`**. En `survival`, los techos
  sugeridos aparecen como tarjeta en Insights ("Sugerido por tu historial:
  Comida ~S/ 150 [Usar como techo]"). En `variable` no se muestran.
- **"Quedan S/ X" en Presupuesto e Insights:** es la diferencia entre
  techos de categorías activas y gasto real del mes. No depende del
  ingreso. La regla "nunca presupuesto restante sin ingreso" aplica solo
  al Home (donde el bloque de presupuesto no aparece sin ingreso en el
  mes).
- **Total de Presupuesto y del Home:** Σ techos de categorías **activas** contra
  **todo** el gasto del mes calendario (`spentInMonth`). El techo de una
  archivada queda guardado y vuelve al desarchivar. Si hubo gasto fuera de los
  techos, Presupuesto lo dice: "Incluye S/ X de categorías sin techo".
- **Pasarse del techo** (barra del Home y de Presupuesto): relleno en
  `expenseFg` con ícono y texto. El ámbar queda solo para el semáforo.
- **Acceso:** fila "Presupuesto" en Ajustes y toque en el bloque de presupuesto
  del Home (que solo aparece en Estable con techos e ingreso en el mes).
- **Qué categorías lista Presupuesto:** todas las activas con techo y, sin
  techo, solo las activas con gasto en los últimos 90 días (la misma ventana de
  los techos sugeridos). Una categoría sin techo y sin gasto en 90 días no
  aparece: la pantalla es para ponerle techo a lo que el usuario ya usa.

- **Explicación de los modos (Fase 2):** ícono ⓘ junto al nombre del espacio
  en el Home → hoja "Modo X" con su explicación y "Ver todos los modos". En
  Ajustes, "Modo actual" (cambia el modo) y debajo "Modos de uso" (pantalla
  de solo lectura con los 3 modos, un ejemplo ficticio rotulado "Ejemplo" y
  check en el actual). Textos en `modeExplanations` (`modes_screen.dart`),
  sin "sueldo".
- **"Sin reserva"** (antes "Sin colchón"): saldo ≤ 0. En Insights el bloque
  de la línea se llama "Reserva".
- **Nombres visibles de los modos** (Ajustes, Insights): Estable, Variable y
  **Supervivencia**. El Onboarding conserva sus 4 opciones; Ajustes ofrece 3,
  porque Mixto se guarda como Variable.

## Ajustes y exportación

- Cambiar el modo o la ventana de runway (7, 14, 21 o 30 días) se aplica al
  instante, sin confirmación.
- **Nombre del espacio:** sin restricción de emojis (fix del día de uso,
  2026-10-09). Se quitan los espacios de los extremos; máximo 30 caracteres
  visibles (un emoji cuenta 1); vacío → null ("Mis cuentas").
- Categorías y fuentes: se archivan, no se borran. La última activa no se
  puede archivar. **Archivar = no ofrecerla para movimientos nuevos; su
  historial sigue contando.** Una categoría archivada con gasto en los últimos
  30 días aparece en el gráfico de gastos de Insights y en todas las métricas.
  No aparece en Presupuesto (ni con techo ni sin techo) ni en el registro. Nombres: máximo 20 caracteres, sin emojis, sin repetir
  (sin distinguir mayúsculas).
- **CSV:** UTF-8 con BOM, separador **punto y coma** (Excel con configuración
  regional de Perú), fin de línea CRLF, del más nuevo al más viejo. Columnas:
  `id;kind;amount_cents;amount;occurred_on;category_or_source;category_or_source_id;note;origin;created_at;updated_at;account_label`.
  `kind` va en español (gasto/ingreso); las fechas, en ISO local.

## Modelo de datos (drift, `lib/data/database.dart`, schemaVersion 5)

Convenciones:

- Dinero en **centavos `INT`**.
- Fecha de evento: `TEXT 'YYYY-MM-DD'` en día local.
- Timestamps: epoch ms.
- `PRAGMA foreign_keys = ON`.

| Tabla | Columnas | Restricciones |
|---|---|---|
| `categories` / `sources` | `id TEXT PK`, `name UNIQUE`, `icon`, `color_hex`, `sort_order`, `archived`, `is_default` | Se archivan, no se borran |
| `entries` | `id`, `kind`, `amount_cents`, `occurred_on`, `category_id?` → categories, `source_id?` → sources, `note?`, `origin`, `account_label?`, `account_id?` → accounts (`ON DELETE SET NULL`), `created_at`, `updated_at` | `kind ∈ {income, expense}`, `amount_cents > 0`, gasto ⇔ solo categoría, ingreso ⇔ solo fuente, `origin ∈ {manual, auto}`; índices `(occurred_on)`, `(kind, occurred_on)` |
| `settings` | `id = 1`, `mode`, `space_name?`, `runway_window_days`, `income_window_days`, `opening_balance_cents?`, `opening_balance_at?`, `onboarding_done` | Ventana de runway 7–90 (default 14); ventana de ingreso ∈ {30, 60, 90} |
| `budgets` | `category_id PK` → categories, `cap_cents > 0` | Techo mensual recurrente |
| `goals` | `id`, `kind ∈ {percent, fixed, cushion}`, `value > 0`, `active`, `created_at` | `percent` en puntos básicos |
| `accounts` (v2) | `id TEXT PK`, `name UNIQUE`, `icon`, `color_hex`, `sort_order`, `archived`, `is_default`, `created_at` | **Vacía hasta la Fase 3** (multi-cuenta): sin UI ni semilla |

- **Semilla v1.** Categorías: Comida, Transporte, Vivienda, Ocio, Salud, Otros.
  Fuentes: Chamba, Venta, Familiar, Préstamo, Otro. Los ids son slugs estables
  (`comida`, `chamba`), útiles para deduplicar en el sync.
- **Sin fila de `settings`** significa onboarding pendiente. La fila se crea al
  terminarlo.
- **Cambio respecto al plan aprobado:** `opening_balance_on TEXT` se reemplazó
  por `opening_balance_at INT` (instante). Hace falta para decidir si un gasto
  del mismo día ya estaba incluido en el saldo inicial (ver Balance).
- **`accounts.created_at`** existe porque las cuentas las creará el usuario
  (no son semilla como categorías y fuentes). Se usará para ordenarlas.
- **`entries.account_id`** es siempre null hasta la Fase 3. `account_label`
  (texto libre) no cambia.
- **Diferido a la Fase 3:** `deleted_at`. (`accounts` existe vacía desde la v2.)

### Migraciones

- Flujo: `dart run drift_dev make-migrations` guarda cada esquema en
  `drift_schemas/saldoclaro/drift_schema_vN.json` y genera
  `lib/data/database.steps.dart` (`stepByStep`) y las clases por versión en
  `test/drift/saldoclaro/generated/`. Correrlo **antes** de cambiar el esquema
  (guarda la versión vigente) y **después** (guarda la nueva).
- `onUpgrade` corre dentro de **una transacción**: drift no envuelve la
  migración por su cuenta y solo sube `user_version` si termina bien. Si un paso
  falla, la base vuelve entera a la versión anterior y puede reintentarse.
- En debug, al abrir una base migrada se corre `PRAGMA foreign_key_check`.
- **v1 → v2** (`migrateV1ToV2`):
  1. `CREATE TABLE accounts` (primero: `account_id` la referencia).
  2. `ALTER TABLE entries ADD COLUMN account_id … REFERENCES accounts(id) ON
     DELETE SET NULL`, sin reconstruir la tabla.
  3. `UPDATE categories SET icon = 'category' WHERE id = 'otros' AND icon =
     'local_mall'`. Solo la fila `otros` y solo si conserva el ícono original:
     una personalización del usuario no se pisa; renombrada o archivada se
     corrige igual; una categoría del usuario con `local_mall` no se toca.
- **v2 → v3** (`migrateV2ToV3`), solo datos, sin cambio de tablas:
  1. Semilla: `color_hex = 'cat:1'…'cat:6'` (comida, transporte, vivienda,
     ocio, salud, otros), sin condición: los hex v2 eran provisionales y nunca
     se mostraron. Aplica también a renombradas y archivadas.
  2. Categorías del usuario (`is_default = 0`, archivadas incluidas), por
     `sort_order, id`: `customCategorySlot(k)` = `cat:${(k + 6) % 9 + 1}`.
  3. Fuentes: no se tocan.
- **v3 → v4** (`migrateV3ToV4`, Fase 3E), solo ADD COLUMN:
  1. `updated_at INTEGER NOT NULL DEFAULT 0` en categories, sources, budgets y
     settings (entries ya lo tenía). Las filas existentes reciben la hora de
     la migración. El 0 es solo el default técnico de SQLite: un test exige
     que ninguna fila quede en 0.
  2. `synced_at INTEGER NULL` en las 5: NULL = nunca sincronizado. Todo lo
     que había queda pendiente y se sube al crear la cuenta (3B).
  3. Tabla `tombstones (entity, row_id, deleted_at)`, PK (entity, row_id),
     `entity` ∈ {entries, budgets}. Se llama `entity` y no `table_name`:
     choca con `Table.tableName` en el código que genera drift.
- **Sync en local (Fase 3E):**
  - Pendiente de subir = `synced_at IS NULL OR synced_at < updated_at`.
  - Toda escritura pone `updated_at = MAX(ahora, updated_at + 1)` (siempre
    crece, aunque el reloj quede quieto o retroceda); las inserciones, la
    hora. Reloj inyectable: `AppDatabase(executor, clock)`.
  - Borrar un movimiento o quitar un techo es un DELETE real y, solo si la
    fila ya se había sincronizado, deja lápida en la misma transacción.
    `setBudget` borra la lápida de ese techo (el techo nuevo gana). Ninguna
    consulta de la app filtra borrados.
  - `accounts` y `goals` no se sincronizan en la Fase 3.
- Tests en `test/drift/saldoclaro/migration_test.dart`: base v1 real con datos,
  esquema migrado idéntico al de una instalación nueva, casos del ícono, FK y
  rollback de una migración que falla a mitad.

## Fórmulas (`lib/domain/metrics.dart`)

`T` = hoy, día local. Los eventos con fecha posterior a `T` **se ignoran en
todas las métricas**. Todo se calcula en enteros salvo donde se indica.

### Saldo inicial ("¿Cuánto tienes hoy?")

- Se guarda como `opening_balance_cents` + `opening_balance_at` (ahora), siempre
  juntos (`AppDatabase.setOpeningBalance`). Un monto sin instante (datos
  viejos) se ignora en los cálculos: cuenta como 0.
- **S/ 0 es un saldo válido.** El usuario de Supervivencia con S/ 0 es un caso
  real. Solo el monto vacío deshabilita "Guardar saldo".
- **Tarjeta en el Home:** aparece siempre que no haya saldo inicial válido,
  sin importar el balance (cambio del 2026-10-09: antes solo con balance ≤ 0).
  Sin saldo inicial, el runway puede verse bien y aun así no reflejar la plata
  real. La X la oculta hasta reiniciar la app (estado en memoria).
- **Hoja:** con monto tecleado no se cierra deslizando, tocando fuera ni con
  Atrás; solo con "Ahora no", que no escribe nada.

### Balance

```
B = opening.cents (o 0) + Σ ingresos − Σ gastos
```

Con saldo inicial, se excluyen los eventos que ya estaban reflejados en él:

- los de un día anterior al saldo inicial, y
- los del mismo día con `created_at` anterior a `opening_balance_at`.

### Ventana efectiva

```
first = min(primer evento de cualquier tipo, día del saldo inicial)
D(W)  = clamp(T − first + 1, 1, W)         // nunca 0
ventana = [T − D + 1, T]
```

`first` usa cualquier tipo de evento. Si usara solo el primer ingreso, un único
ingreso de ayer inflaría el promedio ×30.

### Gasto diario promedio

```
g = Σ gastos(ventana runway_window_days) / D
```

En centavos/día; es `double`.

### Runway

```
R = floor(B · D / G)
```

Es división entera. Equivale a `floor(B / g)` sin perder centavos.

| Caso | Resultado | UI |
|---|---|---|
| Sin eventos ni saldo inicial | `empty` | Estado vacío + CTAs |
| `B ≤ 0` (se evalúa primero) | `noCushion`, 0 días | "Sin reserva" |
| `G = 0` en la ventana | `noSpending` | "Sin gastos en los últimos N días" |
| `D < 7` | `estimated = true` | "estimado · pocos datos" |
| `R > 999` | `days = 999`, `capped = true` | "+999 días" |

Límite conocido: el día de hoy, a medio día, entra completo en la ventana.
Con `D ≥ 7` el sesgo es menor.

### Ingreso típico / gasto típico (cada 30 días)

```
avgIncome30(W) = round(Σ ingresos(ventana W) · 30 / D(W)),  W ∈ {30, 60, 90}
```

Cualquier otro `W` lanza `ArgumentError`. Sin ingresos devuelve 0, y se muestra
"S/ 0" (no se oculta). `avgExpense30` es idéntico, sobre gastos.

**Mismo número en el Home y en Insights (I2 de 1c).** "Ingreso típico 30d" y
"Gasto 30d" del Home y el bloque "Entra y sale" y la frase V1 de Insights usan
`avgIncome30` / `avgExpense30`. Si algún día cambia el criterio (p. ej. mediana
de meses), se cambia en los dos lugares a la vez.

### Ratio entrada/salida (semáforo de 30 días efectivos)

`I` = ingresos y `G` = gastos de la ventana. Se compara sin dividir:

| Condición | Luz |
|---|---|
| `I = 0` y `G = 0` | `none` (gris, "Sin movimientos") |
| `I ≥ G` (incluye `G = 0`, `I > 0`) | `green` |
| `10·I ≥ 7·G` | `amber` (70–99 %) |
| si no | `red` (< 70 %) |

### Ingresos el mismo día

Todas las métricas operan sobre sumas, así que el orden dentro del día no
cambia ningún resultado. `created_at` solo ordena la lista y resuelve el caso
del saldo inicial.

### Racha "sin sobregiro"

Un día `d` está OK si `gasto(d) ≤ umbral`. La racha cuenta días consecutivos
desde hoy hacia atrás:

- **Qué días cuentan:** los días con `gasto(d) ≤ umbral`; el ingreso del día no
  compensa el gasto.
- **Un día sin gastos está OK** y suma a la racha.
- **Hoy cuenta parcialmente:** suma 1 si el gasto registrado *hasta ahora* es
  ≤ umbral. Si hoy ya se pasó, la racha es 0, aunque ayer viniera de 30 días.
- No se cuentan días anteriores a `first`.

Umbral, en este orden (`streakThreshold`):

1. `stable` con techos: `Σ caps / días del mes de T`.
2. Si hay ingreso en los últimos 30 días efectivos: `round(I30 / D30)`, que es
   el ingreso típico diario.
3. Si no: `g` de los últimos 14 días **desde hoy**.
4. Sin datos: `null`, y no se muestra la racha.

**El umbral de racha se congela al abrir Insights.** Se calcula una vez con
datos hasta `T` y se aplica igual a todos los días evaluados. No se recalcula
por cada día del pasado, porque eso hacía que la racha saltara de forma
errática. **No es retroactivo:** cada vez que se abre Insights se calcula el
umbral de hoy y se evalúa la racha con él. No se guarda un umbral por día ni se
reescriben rachas pasadas, y no se persiste nada en la BD.

### Techos sugeridos

```
round(Σ gasto de la categoría en 90 días efectivos · 30 / D(90), a S/ 10)
```

Mínimo S/ 10 si hubo gasto. Se basan solo en el histórico, nunca en el ingreso.

### Insights (1c, `lib/features/insights/`)

Una sola pantalla con scroll, acceso por el ícono `insights_outlined` del
header del Home (los 3 modos). Bloques ya ordenados por modo en
`buildInsightsSummary`:

| Estable | Variable | Supervivencia |
|---|---|---|
| Presupuesto | Entra y sale | Reserva (línea de 140 px) |
| En qué se fue | Tus meses | Racha |
| Racha | En qué se fue | Techos sugeridos |
| Tus meses | Reserva | En qué se fue |
| Reserva | Racha | Tus meses |

- **Frase principal** con alternativas: Estable E1 (techos) → E2 (categoría
  mayor) → E3 (racha). Variable V1 (te sobran/faltan, exige ingreso típico) →
  V2 (montos reales de 30 días) → V3 (mejor mes). Supervivencia S1 (runway) →
  S3 (racha). S2 se descartó: necesita el runway de hoy, justo lo que falta
  cuando S1 no aplica. Si ninguna aplica: sin datos → "Registra unos días más
  y aquí verás tu patrón."; con datos y sin reserva → "Sin reserva por
  ahora."; con datos viejos → "Sin movimientos en los últimos 30 días."
- **`runwaySeries`**: runway de cada uno de los últimos 60 días con la ventana
  del Home; `null` (sin reserva o sin gastos en la ventana) corta la línea.
  Empieza el día del saldo inicial o, sin saldo, el del primer movimiento
  (antes no se sabe cuánto había). Con < 7 puntos: texto de espera.
- **`incomeByClosedMonth`**: meses cerrados y completos (el del primer
  movimiento solo si fue el día 1), últimos 6, con 0 si no hubo ingreso.
  Mejor/peor con ≥ 2 meses.
- **En qué se fue**: 30 días, archivadas incluidas, top 5 sin "Otros"; la
  categoría "Otros" y el resto se pliegan en una fila final piedra. Barras sin
  carril, largo relativo a la fila mayor; texto en ink.
- **Techos sugeridos** (Supervivencia): hasta 3, activas sin techo. [Usar]
  desvanece la fila, guarda el techo y avisa 3 s: "Techo de X guardado. Lo
  verás en Presupuesto cuando cambies a modo Estable."
- Racha en 0 por el gasto de hoy: "Hoy pasaste tu límite diario." en
  inkMuted, sin rojo.

## Sistema visual: "Cuaderno" (`lib/core/theme/`)

### Paleta categórica (1c, validada con `dataviz`)

`color_hex` de una categoría guarda su **slot** (`cat:1`…`cat:9`), no un hex:
el color cambia entre claro y oscuro. `categoryColor(colorHex, brightness)` en
`tokens.dart` lo resuelve; cualquier otro valor cae en piedra.

| Slot | Nombre | Semilla | Claro | Oscuro |
|---|---|---|---|---|
| 1 | terracota | Comida | `#CA653C` | `#D87248` |
| 2 | lago | Transporte | `#2266A4` | `#4E90D2` |
| 3 | mostaza | Vivienda | `#A08318` | `#B0922E` |
| 4 | uva | Ocio | `#634590` | `#8C6EBD` |
| 5 | salvia | Salud | `#8A943A` | `#909A40` |
| 6 | piedra | Otros | `#56524B` | `#726E67` |
| 7 | ciruela | libre | `#B5689D` | `#C274A9` |
| 8 | añil | libre | `#424B9C` | `#5A66B9` |
| 9 | petróleo | libre | `#09919D` | `#029FAB` |

- Todos ≥ 3:1 contra canvas y surface en ambos temas. La piedra es gris a
  propósito (única excepción al piso de croma).
- Categorías del usuario: slots 7, 8, 9 y desde la décima **se reutilizan**
  1, 2… (`(k + 6) % 9 + 1`). Puede haber colores repetidos con 10+ categorías:
  aceptable porque el color nunca va sin su nombre.
- **El gasto por categoría se muestra en barras horizontales rotuladas,
  ordenadas por gasto descendente, no en donut.** Validada con todos los pares,
  la paleta no separa colores como salvia↔mostaza (ΔE 5) o salvia↔terracota
  (CVD ΔE 0.8); en un anillo cualquier par puede quedar junto, en barras cada
  color va pegado a su nombre.
- Texto en `ink`/`inkMuted`, nunca en el color de la categoría.
- `lib/dev/palette_preview.dart` muestra la paleta en el emulador:
  `flutter run -t lib/dev/palette_preview.dart --dart-define=mode=dark`.

Cálido, editorial y sobrio. El color solo comunica significado. Los tokens están
en `tokens.dart` y `ThemeData` claro/oscuro en `app_theme.dart`. Los colores
semánticos se leen con `context.palette`.

| Token | Claro | Oscuro |
|---|---|---|
| canvas / surface / border | `#F7F6F3` / `#FFFFFF` / `#EAE8E3` | `#191918` / `#222220` / `#34332F` |
| ink / inkMuted | `#2B2A27` / `#6F6E69` | `#ECEAE5` / `#A3A19B` |
| ingreso bg/fg | `#EDF3EC` / `#346538` | `#1F2B20` / `#8FC493` |
| gasto bg/fg | `#FDEBEC` / `#9F2F2D` | `#35201F` / `#EFA29E` |
| ámbar bg/fg | `#FBF3DB` / `#8A5D00` | `#332A12` / `#E3B85C` |
| attention (3D) | `#CA653C` | `#D87248` |

- **Tipografía:**
  - **Newsreader 16pt Medium**, solo para el número principal (52 sp) y los
    títulos (26 sp). Nunca por debajo de 22 sp.
  - **Geist** 400/500/600 para todo lo demás. Los montos llevan
    `tabularFigures`.
  - Las dos fuentes van como asset, con licencia OFL. Sin w700.
- **Espaciado:** base 4 (4/8/12/16/24/32/48), margen lateral 20, CTA de 56 de alto.
- **Radios:** chip 8, botón 10, tarjeta 12, hoja de registro 20.
- **Movimiento:**
  - resorte por defecto: amortiguación 1,0, respuesta 0,35 s;
  - hoja de registro: amortiguación 0,85, respuesta 0,30 s;
  - al presionar: escala 0,97 en 100 ms;
  - número principal: 250 ms; semáforo: 200 ms;
  - con "reducir movimiento": fundido de 150 ms.
- **CTAs "− Gasto" y "+ Ingreso":** mismo tamaño y peso visual. Solo cambia el
  color semántico.

## Estado del proyecto al cierre de la Fase 1 (2026-10-12)

- **Hecho:** app local sin red ni login. Onboarding de 2 pasos; Home por modo
  (Estable, Variable, Supervivencia); registro en 2 toques con borrador;
  saldo inicial; Ajustes con catálogos y CSV; Presupuesto por techos (solo
  Estable); Insights con barras, línea de reserva, racha, meses y techos
  sugeridos.
- **Datos:** drift `schemaVersion 3` (v2: `accounts` vacía +
  `entries.account_id`; v3: slots de color `cat:N`). Migraciones en una
  transacción, probadas con bases reales v1 y v2 y en el celular del usuario.
- **Calidad:** 413 tests (unitarios de métricas, armado de pantallas,
  widgets, migraciones), verificados con mutantes; `flutter analyze` limpio;
  code-review y security-review de la 1c cerrados (sin hallazgos de
  seguridad).
- **Tags:** `fase-1a-completa`, `fase-1b-completa-v3`, `fase-1c-completa`,
  `fase-1-completa-v2`.
- **Pendiente para Fase 2** (detalle en `tasks/todo.md`, feedback del
  2026-10-12): legal y beta cerrada; explicar los modos; reemplazar "Sin colchón"
  (hecho en Fase 2: "Sin reserva"); tema manual; calculadora "¿cuánto puedo gastar hoy?"; historial
  completo; cap del sugerido a gasto real × 1.2.
- **Fuera de alcance hasta su fase:** sync (3), multi-cuenta (3), gasto
  recurrente y captura de notificaciones (4), IA (5).

## Historial (Fase 4B)

`lib/features/history/`: `filters.dart` (lógica pura, TDD) y `history_screen.dart`.
Acceso: "Ver todo" en Recientes del Home y la fila "Historial" en Ajustes.

- **Filtra en memoria** sobre el mismo stream de movimientos que el Home (sin
  paginar en SQL): una lista perezosa da el scroll infinito. Techo conocido:
  decenas de miles de movimientos.
- **Filtros:** tipo (Todos / Gastos / Ingresos; cambiar el tipo limpia los
  chips), chips de categoría o fuente según el tipo (activas + archivadas con
  movimientos; se suman con O) y Fecha: Todo, Este mes, Mes pasado, Últimos 30
  días, Últimos 90 días o Personalizado (calendario de rango). La fila de tipo y
  Fecha se desliza en pantallas angostas. Los filtros duran mientras la pantalla
  está abierta.
- **Búsqueda en vivo** en la nota y el nombre de la categoría o fuente, sin
  mayúsculas, tildes ni ñ (`normalizeForSearch`).
- **Agrupada por día** siempre: Hoy, Ayer, "lun 5 oct"; de otro año, con el año.
- **Totales** del filtro: "N movimientos · Gastos S/ X · Ingresos S/ Y" en una
  línea si cabe; si no, el conteo arriba y los montos (completos) abajo.
- **Editar:** tocar un movimiento (aquí o en Recientes) abre la hoja de registro
  en modo edición: precargada, "Guardar cambios", el tipo no cambia, el borrador
  no se lee ni se escribe, la categoría o fuente archivada del movimiento aparece
  como "Nombre (archivada)". `updateEntry` sube `updated_at` (el sync lo vuelve a
  subir); sin cambios no escribe.
- **Borrar:** deslizar a la izquierda → "¿Borrar este movimiento?" →
  `deleteEntry` (lápida si estaba sincronizado). La fila sale de la lista en el
  acto, sin esperar a la base. Acción de accesibilidad "Borrar" con la misma
  confirmación.

## Estado del proyecto al cierre de la Fase 3 (2026-10-13)

- **Hecho:** sync opcional con Supabase (proyecto saldoclaro-prod, São Paulo).
  - 3A (`fase-3a`): esquema del servidor, RLS por usuario, trigger
    last-write-wins y `delete_account()`.
  - 3E (`fase-3e`): local v4 con `updated_at`, `synced_at` y lápidas.
  - 3B (`fase-3b`): cuenta opcional (crear con código, entrar, recuperar,
    cerrar sesión, borrar cuenta) y push.
  - 3C (`fase-3c`): pull, motor, scheduler y estado; local v5 (`sync_cursors`).
  - 3D (`fase-3d`): ícono de estado en el Home y hoja de detalle.
  - Textos (`fase-3-textos`): política y términos con el sync, consentimiento
    explícito al crear la cuenta (Ley 29733), ficha de Play y landing.
- **Calidad:** 600 tests y 1 skip (el e2e contra Supabase real, que espera el
  SMTP); `flutter analyze` limpio; convergencia de dos teléfonos probada con
  semillas aleatorias; mutantes en las partes nuevas (ver pendiente abajo).
- **Tag de cierre:** `fase-3-completa`.
- **Pendientes del usuario:**
  - [ ] Configurar SMTP propio (Gmail dedicado) en saldoclaro-prod y
    saldoclaro-test, con las plantillas de `supabase/plantillas/`.
  - [ ] Inscribir el banco de datos personales (Ley 29733) y reemplazar
    `[CÓDIGO DE INSCRIPCIÓN]` en la política.
  - [x] Apagar "Write audit logs to the database" en los dos proyectos.
  - [ ] Confirmar que `saldoclaro.oficial@gmail.com` es el correo definitivo.
  - [ ] Crear la cuenta de Play Console (25 USD).
- **Pendientes técnicos:**
  - [ ] Mutation testing de pull/engine/scheduler/push: 27 mutantes restantes,
    en lotes de 5 a 10.
  - [ ] Test e2e contra Supabase real (quitar el skip cuando haya SMTP).
- **Para la Fase 4** (detalle en `tasks/todo.md`): consentimiento demostrable
  (fecha y versión aceptadas), aviso de cambios de política en la app,
  multi-cuenta, captura, recordatorios e historial.

## Legal y Play Store (Fase 2)

- Política de privacidad y Términos viven en `assets/legal/*.md` (la app los
  muestra con `LegalScreen`) y en `docs/play-store/` para publicarlos; un test
  exige que sean idénticos. Correo de contacto provisional `saldoclaro.oficial@gmail.com`
  (por confirmar, ver `tasks/todo.md`).
- **Fase 3 (textos):** la política y los términos explican el sync opcional
  (Supabase, servidores en São Paulo, transferencia internacional, banco de datos
  de la Ley 29733, derechos, mayores de 18). Titular: Edson More, Lima. Queda un
  placeholder que no se publica: `[CÓDIGO DE INSCRIPCIÓN]` (ver `tasks/todo.md`). "Crear cuenta" exige marcar "Acepto la Política de privacidad
  y que mis datos se guarden fuera del Perú." (los ingresos son dato sensible en
  la Ley 29733); sin marcar, el botón queda deshabilitado y Enter no hace nada.
- La release declara solo `INTERNET` (permiso normal, Android no lo pregunta); sin
  cuenta la app no abre conexiones.
  Se mantiene la copia de seguridad de Android y la política lo dice.
- Firma: con `android/key.properties`, keystore de subida; sin él, firma de
  debug (el build de release no se rompe). Guía en `docs/play-store/firma.md`.
- Package `com.saldoclar.app`, definitivo. Versión `0.2.0+1`.

## Cuenta opcional (Fase 3B)

- Ajustes → "Sincronizar con la nube". Sin cuenta todo funciona igual y la app no
  abre conexiones (Supabase sin sesión guardada no hace llamadas; `debug: false`).
- Correo + contraseña (≥ 6). Confirmación al crear la cuenta y recuperación de la
  contraseña con **código de 6 dígitos** (`verifyOTP` signup / recovery; plantillas
  con `{{ .Token }}` en `supabase/plantillas/`). Requiere SMTP propio en Supabase.
- Toda operación de cuenta tiene **timeout de 15 s** y errores en español
  (`AuthFailure`), sin texto técnico.
- **Crear cuenta sube todo lo del teléfono** sin preguntar (la cuenta nueva está
  vacía). Entrar con una cuenta existente: ver D5 en la Fase 3C.
- **Cerrar sesión o borrar la cuenta** deja los datos en el teléfono y vuelve todo a
  pendiente (`detachSync`): otra cuenta recibiría todo.
- Borrar cuenta: escribir BORRAR → RPC `delete_account()`. Página web para pedirlo:
  `docs/landing/borrar-cuenta.html` (mailto, plazo 30 días).
- `push()` (`lib/features/sync/push.dart`), lo reutiliza la 3C: lotes de 200 por
  tabla en el orden de las FK; si un lote falla por datos, fila por fila; un error de
  datos deja esa fila pendiente y sigue; un error de red corta (lo demás queda
  pendiente). `synced_at` = el `updated_at` que se mandó, **solo si el servidor la
  aceptó** (3C: ver "descartes"). Filas con `deleted_at: null` (revive un techo
  quitado); lápidas por UPDATE al final. Nunca dos a la vez.
- Upsert con `defaultToNull: false` (`Prefer: missing=default`): `user_id` no se
  manda y toma `auth.uid()`; con el default de postgrest quedaría NULL.

## Sincronización (Fase 3C)

Código en `lib/features/sync/`: `pull.dart`, `sync_engine.dart`, `scheduler.dart`,
`status.dart`. Sin SQL nuevo en el servidor.

- **Motor** (`SyncEngine`): un solo candado para todo; `sync()` = primero pull,
  después push (el de la 3B). Como máximo uno corriendo y uno esperando.
- **Cursor** por tabla en `sync_cursors` (v5): el `server_updated_at` más alto
  bajado, tal como lo da el servidor; nunca la hora del teléfono. Se pide desde
  cursor − 10 s (solapamiento: transacciones que confirman tarde). `detachSync`
  borra los cursores.
- **Bajada:** páginas de 1000; se descarga en orden inverso a las FK (budgets,
  entries, settings, sources, categories) y se aplica en el orden de las FK, todo
  en **una transacción** junto con los cursores. Una fila que no entra (p. ej. un
  CHECK local) se salta con un savepoint y cuenta como problema.
- **Reglas al aplicar una fila remota R** (L local, T lápida local): R.updated_at
  ≥ L.updated_at → gana R (empate: el servidor); menor → se ignora (la sube el
  push). Sin L: con T, si R ≥ T se recrea (o se confirma el borrado) y T se va;
  si no, se ignora. R borrada → borra L sin dejar lápida. Al aplicar no se usa
  `bumped()`: queda el updated_at del servidor y `synced_at` igual.
- **Nombre repetido** (UNIQUE solo en el teléfono): la fila LOCAL pasa a
  "Nombre (n)" (el primer n libre) y queda pendiente; los dos teléfonos terminan
  con ambos nombres.
- **Descartes:** el trigger descarta en silencio una versión no más nueva (p. ej.
  un teléfono con el reloj atrasado vuelve a poner un techo que otro quitó). El
  servidor devuelve qué filas aceptó (`.select()`); las descartadas no se marcan,
  se traen por clave y se aplican sin mover los cursores (`Puller.reconcile`). Sin
  esto los teléfonos divergían para siempre (lo encontró el test aleatorio).
- **Lápidas con el reloj atrasado:** `deleted_at = MAX(ahora, updated_at + 1)`.
- **D5, primer contacto con una cuenta** (`neverSynced`: sin cursores ni filas
  sincronizadas): nube vacía → sube todo; teléfono solo con semilla → usa la nube
  sin preguntar; los dos con datos → `needsChoice` y no sube nada hasta elegir
  "Unir" (los ajustes de la nube ganan) o "Usar solo los de la nube" (con
  confirmación). Nada se persiste: si cierra la app sin elegir, se pregunta de nuevo.
- **D6:** last-write-wins puro, también borrado contra edición.
- **Errores:** red/5xx/429 → `offline` (se reintenta en el próximo disparador).
  401/JWT → refrescar la sesión una vez y reintentar; sin red → `offline`; sesión
  inválida → cerrar la sesión local, `needsLogin`; los datos y lo pendiente se
  quedan. Cerrar sesión por cualquier causa → `detachSync`.
- **Disparadores** (`SyncScheduler`): al abrir, al volver (`resumed`), 3 s después
  de la última escritura **si quedó algo pendiente** (las escrituras del propio
  pull no dejan pendientes: sin bucle), cada 60 s en primer plano (se pausa en
  background), botón "Sincronizar ahora". Al ir al background: solo subir si hay
  pendientes (nunca antes de D5). Sin sesión: ni timers ni red. Sin sync en
  background (D3).
- **Estado** (`SyncStatus`): off, syncing, ok(hora), offline, needsLogin,
  needsChoice, issues(n). Texto en "Sincronizar con la nube" e ícono en el
  Home (Fase 3D).
- **Tests:** `pull_test`, `engine_test`, `scheduler_test` (fake_async),
  `two_phones_test` (dos bases contra un servidor falso, más una prueba aleatoria
  con semilla: `--dart-define=SEED=n --dart-define=ROUNDS=n` para explorar).

## Indicador de sync (Fase 3D)

`lib/features/sync/sync_indicator.dart`. Ícono de 20 px (área táctil de 48) en el
header del Home, en el grupo derecho antes de Insights; en los 3 modos.

| Estado | Ícono | Color |
|---|---|---|
| off | ninguno (no ocupa lugar) | |
| syncing | spinner de 16 px, trazo 1.5 (con "reducir movimiento": `cloud_sync_outlined`) | inkMuted |
| ok | `cloud_done_outlined` | inkMuted |
| offline | `cloud_off_outlined` (no escala aunque dure horas) | inkMuted |
| needsLogin | `error_outline` | expenseFg |
| needsChoice | `cloud_outlined` + punto de 6 px | attention (terracota) |
| issues(n) | `sync_problem_outlined`; badge con n solo si n > 1, "9+" desde 10 | expenseFg |

- **Spinner:** aparece si el sync dura más de 1 s y se queda al menos 600 ms
  (el polling no hace parpadear el header).
- **Hoja** (al tocar): título y texto por estado, "Última vez"
  (`relativeSyncTime`: hace un momento, hace N min, hace N h, ayer a las HH:mm,
  d MMM) y "Por subir" (`pendingCount`: filas pendientes + lápidas), solo en
  syncing/ok/offline/issues. Botón: "Sincronizar ahora" (spinner en el botón, la
  hoja queda abierta, sin snackbar), "Elegir qué datos usar" (needsChoice) o
  "Volver a entrar" (needsLogin). Links: "Ajustes de sync" y "Cerrar sesión"
  (solo con sesión); en needsLogin, "Ahora no" (`dismissLogin()`: pasa a off).
- **Último sync bueno** persistido en `shared_preferences` (`sync.lastOkAt`,
  epoch ms): se ve aunque se reabra la app sin conexión; se borra al cerrar
  sesión por cualquier causa.
- **Token `attention`** (`#CA653C` / `#D87248`): "requiere una acción tuya".
  Mismo tono que la categoría 1, pero es otro significado.

## Aprendido en la 1c

- **Validar la paleta con todos los pares, no solo vecinos.** Con orden fijo
  y categorías sin gasto, cualquier par puede quedar junto; salvia↔mostaza
  (ΔE 5) no se distinguen. Por eso el gasto va en barras rotuladas.
- **Guardar el slot, no el hex** (`cat:N`): el color cambia entre temas.
- **Un mismo número, una sola fórmula:** el total de Presupuesto y el del Home
  (todo el gasto del mes contra techos de activas), y el ingreso típico del
  Home e Insights, salen de las mismas funciones.
- **Las alternativas de una frase tienen que poder aplicarse:** V2 y S2
  repetían la condición de la frase anterior; los tests lo mostraron.
- **Texto de espera solo sin datos:** con historial, "registra unos días más"
  es falso.
- **Capturas del emulador "Resizable":** tiene 2 displays; usar
  `adb exec-out screencap -p -d <id del display 0>` y, si sale negro, lanzarlo
  con `-gpu swiftshader_indirect`.

## Stack

- Flutter 3.44 (stable), Dart ^3.12, `flutter_riverpod` ^2.6.
- `drift` ^2.35 + `drift_flutter` (persistencia). Gráficos propios (barras con
  widgets, línea de runway con `CustomPainter`): sin librería de gráficos.
- `intl`, `uuid`, `share_plus` + `path_provider` (CSV).
- `shared_preferences`: para `core/legal/legal_acceptance_store.dart` (Fase 2) y
  los borradores del registro. **Excepción documentada (3D):** `sync.lastOkAt`,
  la hora del último sync bueno. Es solo un timestamp, ningún dato del usuario.
- `supabase_flutter` (Fase 3B) solo para el sync opcional: sin sesión no abre
  conexiones. En la Fase 1 habían salido `supabase_flutter`, `http`, `pdf`,
  `google_fonts` (descarga fuentes en runtime; en 1b la fuente va como asset), `local_auth`,
  `permission_handler`, `flutter_local_notifications`, `timezone` y
  `flutter_vector_icons`.

## Comandos

```
flutter pub get
dart run build_runner build      # regenera lib/data/database.g.dart
flutter test                     # suite completa
flutter test test/domain         # solo métricas
flutter analyze
flutter build apk --debug
```

En Windows, `flutter pub get` pide activar el Modo de desarrollador (symlinks de
plugins): `start ms-settings:developers`.

## Estructura

```
lib/
├── main.dart, app.dart     → arranque: Onboarding si no hay settings, si no Home
├── domain/metrics.dart     → funciones puras (sin Flutter ni BD)
├── data/                   → drift (database.dart + .g.dart), providers Riverpod
├── core/utils/formatters.dart
└── features/               → pantallas de 1b/1c; capture/ archivado
test/
├── domain/metrics_test.dart
├── data/database_test.dart
├── app_test.dart           → ruteo de arranque
└── features/capture/, widget_test.dart, services_test.dart → parser, redactor, categorizador
```

### Código archivado

- **Captura (Fase 4):** es lo único excluido del analizador
  (`analysis_options.yaml`). Ver `lib/features/capture/README.md`.
- **Borrado** (recuperable con `git checkout v1-supabase -- <ruta>`):
  - IA, chat, pareja, ciclos de cobro, gamificación y cuentas;
  - `insights_engine` (reemplazado por `metrics.dart`);
  - el dashboard, salvo `app_recognition_screen.dart`, que es de captura;
  - `auth`, `legal/presentation`, `profile`, `reports`;
  - `core/{config, network, providers, security, theme}`.

  En 1b se rescatan del tag, según haga falta, `icon_catalog.dart`,
  `export_service.buildCsv` y las pantallas de catálogos.

## Estilo de código

- Lógica de dinero solo en `domain/`, como funciones puras con `today` inyectado
  (nunca `DateTime.now()` adentro).
- Montos `int` en centavos. Se formatean a soles solo en la UI
  (`Formatters.currency(cents / 100)`).
- Fechas de dominio con `day()` / `dayOf()`, en UTC a medianoche.

## Estrategia de pruebas

- **TDD obligatorio en `domain/metrics.dart`.** Cada caso borde de esta spec
  tiene su test en `test/domain/metrics_test.dart`.
- La BD se prueba en memoria (`NativeDatabase.memory()`): semilla, CHECKs y FK.
- Los widgets no usan TDD. El ruteo de arranque tiene un test de humo.

## Límites

- **Siempre:** correr `flutter test` y `flutter analyze` antes de cerrar una
  tarea; mostrar el wireframe antes de codear una pantalla.
- **Preguntar antes:** cambiar el esquema (requiere migración y subir
  `schemaVersion`), agregar dependencias, cualquier dependencia de red, usar las
  skills prohibidas.
- **Nunca:** borrar el código de captura; guardar dinero en `double`; mostrar
  "presupuesto restante" sin ingreso en el Home; llamar "sueldo" a un ingreso.

## Criterios de éxito de la Fase 1a

- [x] `flutter test` en verde, con los casos borde de esta spec cubiertos.
- [x] `flutter analyze` sin issues.
- [x] `flutter build apk --debug` OK, con el manifest sin servicio de
  notificaciones.
- [x] El arranque va a Onboarding sin settings, y a Home cuando
  `onboarding_done = true`.
