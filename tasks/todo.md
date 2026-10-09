# Tareas — Fase 1

## 1a — Dominio y datos ✅
- [x] Tag `v1-supabase`; borrar IA, pareja, ciclos de cobro, gamificación y cuentas
- [x] pubspec sin red; drift agregado
- [x] Manifest sin NotificationService, BIND_NOTIFICATION_LISTENER_SERVICE ni INTERNET
- [x] `lib/domain/metrics.dart` + 49 tests (TDD)
- [x] Esquema drift v1 + semilla + 8 tests de BD
- [x] `main.dart`/`app.dart` sin Supabase, auth, permisos ni consentimiento + test de ruteo
- [x] `lib/features/capture/README.md`
- [x] `SPEC.md`

### Checkpoint 1a — revisión humana ⏳

## 1b — Pantallas núcleo (skills: minimalist-ui + apple-design)
- [ ] Tokens visuales + fuente como asset (reemplaza `core/theme/app_theme.dart`)
  - Verify: analyze limpio, sin google_fonts
- [ ] Onboarding de 2 pasos → crea la fila de settings (Mixto → variable + "Chamba" favorita)
  - Verify: test de ruteo; widget manual
- [ ] Hoja de registro (gasto/ingreso, mismo widget) + teclado propio
  - Verify: ≤2 toques desde Home; insert válido en drift
- [ ] Home adaptativo por modo + tarjeta/bottom sheet "¿Cuánto tienes hoy?" (wireframe 3.8)
- [ ] Ajustes: modo, nombre, saldo inicial, ventana de runway, catálogos, CSV
### Checkpoint 1b

## 1c — Presupuesto + Insights (skills: design-taste-frontend + dataviz)
- [ ] Pantalla de Presupuesto (solo stable)
- [ ] Insights: donut, línea de runway, mejor/peor mes, racha (umbral congelado), frases
- [ ] Tarjeta de techos sugeridos (survival)
### Checkpoint 1c — code-review + security-review
