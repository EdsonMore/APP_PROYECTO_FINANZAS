# SaldoClaro

App de finanzas personales para Android que responde dos preguntas:
**¿en qué se me va la plata?** y **¿me va a alcanzar?**

Está pensada para quien no tiene un ingreso fijo: freelancers, gente con
ingresos variables o que hoy vive de entradas sueltas. Funciona desde el día 1
con solo gastos, sin pedir sueldo ni día de pago, y calcula cuántos días te
alcanza la plata con tu ritmo de gasto real.

Todo se guarda en el teléfono. No hay login, ni servidor, ni conexión a internet.

## Pantallas

| Onboarding | Home | Registro |
|---|---|---|
| ![Onboarding: ¿Cómo son tus ingresos?](docs/screenshots/fase-1b-onboarding/paso1-claro.png) | ![Home en modo Variable: te alcanza para ~68 días](docs/screenshots/fase-1-final/home-variable-claro.png) | ![Registro de gasto con teclado propio](docs/screenshots/fase-1b-registro/registro-gasto-monto-claro.png) |

- **Onboarding de 2 pasos:** elige cómo son tus ingresos (Estables, Variables,
  Mixtos o Sin ingreso fijo) y, si quieres, un nombre. No pide montos.
- **Home adaptativo por modo:**
  - Estable: cuánto te queda del presupuesto del mes;
  - Variable: cuántos días te alcanza, con ingreso típico y gasto de 30 días;
  - Supervivencia: cuántos días te alcanza y cuánto gastas al día.

  Además: semáforo de entradas y salidas, en qué se va la plata y movimientos
  recientes con Deshacer.
- **Registro en 2 toques:** teclado propio, categoría o fuente preseleccionada
  y borrador que sobrevive si cierras la app.
- **Ajustes:** modo, nombre, saldo inicial, ventana del cálculo, categorías y
  fuentes, exportación a CSV (lista para Excel en Perú).

| Presupuesto | Insights (Estable) | Insights (Supervivencia) |
|---|---|---|
| ![Presupuesto con techos por categoría](docs/screenshots/fase-1c-presupuesto/presupuesto-con-techos-claro.png) | ![Insights en modo Estable](docs/screenshots/fase-1c-insights/insights-estable-claro.png) | ![Insights en modo Supervivencia con la línea de colchón](docs/screenshots/fase-1c-insights/insights-supervivencia-claro.png) |

| Ajustes | Saldo inicial | Insights (oscuro) |
|---|---|---|
| ![Ajustes](docs/screenshots/fase-1b-ajustes/ajustes-principal-claro.png) | ![Hoja de saldo inicial](docs/screenshots/fase-1b-saldo/saldo-hoja-claro.png) | ![Insights en modo Estable, tema oscuro](docs/screenshots/fase-1c-insights/insights-estable-oscuro.png) |

- **Presupuesto (modo Estable):** un techo mensual por categoría contra el
  gasto real, con sugerencias sacadas de tu historial.
- **Insights:** en qué se fue la plata en 30 días, cómo se movió tu colchón en
  60 días, tu racha sin pasarte del límite diario y tus mejores y peores meses.
  El orden de los bloques cambia según el modo.

Más capturas, en claro y oscuro, en [`docs/screenshots/`](docs/screenshots/).

## Stack

- **Flutter** (stable) + **Riverpod** para el estado.
- **drift** (SQLite) para la persistencia local, con streams reactivos: el Home
  se recalcula solo al guardar.
- **Sin dependencias de red.** Las fuentes Newsreader y Geist van como asset
  (licencia OFL).
- Los gráficos son propios (barras con widgets y la línea con `CustomPainter`),
  sin librería de gráficos. La paleta de categorías se validó para daltonismo.
- Las métricas (runway, promedios, semáforo, presupuesto, insights) son funciones puras
  en `lib/domain/metrics.dart`, escritas con TDD. El dinero se maneja siempre
  en centavos enteros.

## Cómo compilar

```bash
flutter pub get
dart run build_runner build   # genera lib/data/database.g.dart (drift)
flutter run
```

```bash
flutter test      # suite completa
flutter analyze
```

En Windows, `flutter pub get` pide activar el Modo de desarrollador
(`start ms-settings:developers`).

## Estado

**Fase 1 completa** (tag `fase-1-completa-v2`): la app funciona de punta a
punta en el teléfono, sin red. 413 tests, `flutter analyze` limpio.

- **1a:** modelo de datos (drift), fórmulas en `metrics.dart` y sistema
  visual "Cuaderno".
- **1b:** Onboarding, Home por modo, registro en 2 toques, saldo inicial y
  Ajustes con exportación a CSV.
- **1c:** paleta de categorías (migración v3), Presupuesto e Insights.

## Roadmap

| Fase | Qué entra |
|---|---|
| **1** ✅ | App local completa: registro, Home por modo, Presupuesto, Insights |
| **2** | Legal (privacidad, términos) y beta cerrada en Play Store. Del uso real: explicación de los modos, texto de "Sin colchón", tema manual, calculadora "¿cuánto puedo gastar hoy?", historial completo |
| **3** | Sync opcional con Supabase, multi-cuenta, cuenta compartida |
| **4** | Gasto recurrente (recordatorios de facturas) y captura de notificaciones como experimento (puede no funcionar en todos los fabricantes) |
| **5** | IA real, siempre detrás de un backend proxy (nunca con API keys en el APK) |

El detalle de producto, fórmulas y decisiones está en [`SPEC.md`](SPEC.md). El
plan de trabajo, en [`tasks/todo.md`](tasks/todo.md).
