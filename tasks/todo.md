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
- [x] Tokens visuales + fuentes como asset (`fase-1b-sistema-visual`)
- [x] Onboarding de 2 pasos → crea la fila de settings (Mixto → variable) (`fase-1b-onboarding`)
- [x] Hoja de registro gasto/ingreso + teclado propio + borrador persistente (`fase-1b-registro`)
- [x] Home: borrar botones de debug en el primer commit de la fase.
- [ ] Home: implementar Deshacer con las reglas ya anotadas (ver abajo).
- [ ] Home adaptativo por modo + tarjeta/bottom sheet "¿Cuánto tienes hoy?" (wireframe 3.8)
  - Aviso "Deshacer" después de guardar un movimiento (C3):
    - el aviso dura 4 s;
    - "Deshacer" hace un DELETE real en `entries` (no borrado lógico), sin confirmación;
    - después aparece "Movimiento eliminado" por 2 s, sin acción.
  - Texto del semáforo más corto, para que no pase a 2 líneas en 720p. Mostrar el texto exacto antes de codear.
- [ ] Ajustes: modo, nombre, saldo inicial, ventana de runway, catálogos, CSV
### Checkpoint 1b

## Para 1c o 2
- [ ] Tocar un movimiento → editarlo. Deslizarlo → borrarlo.
- [ ] Semáforo: comparar el mes actual con el anterior ("12 % más que septiembre"). Solo con al menos 2 meses de datos.
- [ ] Tarjeta "¿Cuánto tienes hoy?" en el Home: entra con la hoja de saldo inicial (paso siguiente al Home).

## 1c — Presupuesto + Insights (skills: design-taste-frontend + dataviz)
- [ ] Pantalla de Presupuesto (solo stable)
- [ ] Insights: donut, línea de runway, mejor/peor mes, racha (umbral congelado), frases
- [ ] Tarjeta de techos sugeridos (survival)
### Checkpoint 1c — code-review + security-review
