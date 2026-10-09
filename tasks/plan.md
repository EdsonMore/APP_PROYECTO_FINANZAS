# Plan de implementación: SaldoClaro Fase 1

Spec: `SPEC.md`. Lista de tareas: `tasks/todo.md`.

## Decisiones de arquitectura
- drift en vez de sqflite: tipos al compilar, `.watch()` → `StreamProvider`,
  migraciones versionadas y BD en memoria para tests.
- Las métricas son funciones puras con `today` inyectado. La UI nunca calcula dinero.
- El código legacy queda excluido del analizador hasta adaptarlo (1b) o reescribirlo (Fase 3).

## Orden
1a dominio/datos ✅ → 1b pantallas núcleo → 1c Presupuesto + Insights → cierre.

## Riesgos
| Riesgo | Impacto | Mitigación |
|---|---|---|
| Métricas mal definidas → la app miente | Alto | TDD + casos borde en SPEC.md |
| UI que calcula por su cuenta | Medio | Providers derivados que solo llaman a `metrics.dart` |
| Cambio de esquema en Fase 3 | Medio | Migración drift v2 + `drift_dev schema dump` antes de tocar v1 |
