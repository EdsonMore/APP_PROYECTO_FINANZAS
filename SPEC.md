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

## Modelo de datos (drift, `lib/data/database.dart`, schemaVersion 1)

Convenciones:

- Dinero en **centavos `INT`**.
- Fecha de evento: `TEXT 'YYYY-MM-DD'` en día local.
- Timestamps: epoch ms.
- `PRAGMA foreign_keys = ON`.

| Tabla | Columnas | Restricciones |
|---|---|---|
| `categories` / `sources` | `id TEXT PK`, `name UNIQUE`, `icon`, `color_hex`, `sort_order`, `archived`, `is_default` | Se archivan, no se borran |
| `entries` | `id`, `kind`, `amount_cents`, `occurred_on`, `category_id?` → categories, `source_id?` → sources, `note?`, `origin`, `account_label?`, `created_at`, `updated_at` | `kind ∈ {income, expense}`, `amount_cents > 0`, gasto ⇔ solo categoría, ingreso ⇔ solo fuente, `origin ∈ {manual, auto}`; índices `(occurred_on)`, `(kind, occurred_on)` |
| `settings` | `id = 1`, `mode`, `space_name?`, `runway_window_days`, `income_window_days`, `opening_balance_cents?`, `opening_balance_at?`, `onboarding_done` | Ventana de runway 7–90 (default 14); ventana de ingreso ∈ {30, 60, 90} |
| `budgets` | `category_id PK` → categories, `cap_cents > 0` | Techo mensual recurrente |
| `goals` | `id`, `kind ∈ {percent, fixed, cushion}`, `value > 0`, `active`, `created_at` | `percent` en puntos básicos |

- **Semilla v1.** Categorías: Comida, Transporte, Vivienda, Ocio, Salud, Otros.
  Fuentes: Chamba, Venta, Familiar, Préstamo, Otro. Los ids son slugs estables
  (`comida`, `chamba`), útiles para deduplicar en el sync.
- **Sin fila de `settings`** significa onboarding pendiente. La fila se crea al
  terminarlo.
- **Cambio respecto al plan aprobado:** `opening_balance_on TEXT` se reemplazó
  por `opening_balance_at INT` (instante). Hace falta para decidir si un gasto
  del mismo día ya estaba incluido en el saldo inicial (ver Balance).
- **Diferido a la Fase 3:** `deleted_at` y la tabla `accounts`.

## Fórmulas (`lib/domain/metrics.dart`)

`T` = hoy, día local. Los eventos con fecha posterior a `T` **se ignoran en
todas las métricas**. Todo se calcula en enteros salvo donde se indica.

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
| `B ≤ 0` (se evalúa primero) | `noCushion`, 0 días | "Sin colchón"; tarjeta "¿Cuánto tienes hoy?" |
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

- Hoy cuenta si todavía está OK.
- Un día sin gastos está OK.
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
errática.

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
- `drift` ^2.35 + `drift_flutter` (persistencia), `fl_chart` (gráficos).
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
