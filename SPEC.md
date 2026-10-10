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
- Nunca se muestra "presupuesto restante" sin ingreso registrado en el mes.
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

## Modelo de datos (drift, `lib/data/database.dart`, schemaVersion 3)

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
| `B ≤ 0` (se evalúa primero) | `noCushion`, 0 días | "Sin colchón" |
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

### Pendientes para 1c (no están en 1a)

- Serie de runway para la línea de 60 días: `R(d)` con la misma fórmula,
  calculado al vuelo.
- Mejor y peor mes de ingreso.
- "Tu colchón bajó X %": `(B_fin − B_inicio) / B_inicio`, solo si `B_inicio > 0`.

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

## Stack

- Flutter 3.44 (stable), Dart ^3.12, `flutter_riverpod` ^2.6.
- `drift` ^2.35 + `drift_flutter` (persistencia). Gráficos propios (barras con
  widgets, línea de runway con `CustomPainter`): sin librería de gráficos.
- `intl`, `uuid`, `share_plus` + `path_provider` (CSV).
- `shared_preferences`: solo para `core/legal/legal_acceptance_store.dart` (Fase 2).
- **Sin dependencias de red.** Salieron `supabase_flutter`, `http`, `pdf`,
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
  "presupuesto restante" sin ingreso; llamar "sueldo" a un ingreso.

## Criterios de éxito de la Fase 1a

- [x] `flutter test` en verde, con los casos borde de esta spec cubiertos.
- [x] `flutter analyze` sin issues.
- [x] `flutter build apk --debug` OK, con el manifest sin servicio de
  notificaciones.
- [x] El arranque va a Onboarding sin settings, y a Home cuando
  `onboarding_done = true`.
