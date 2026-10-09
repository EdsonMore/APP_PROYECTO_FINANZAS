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
- [x] Home: Deshacer con las reglas anotadas (4 s, DELETE real, "Movimiento eliminado" 2 s, cierre deslizando).
- [x] Home adaptativo por modo (`fase-1b-home`). La tarjeta "¿Cuánto tienes hoy?" pasó al paso de su hoja.
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
- [x] Tarjeta "¿Cuánto tienes hoy?" en el Home + hoja de saldo inicial (`fase-1b-saldo`). S/ 0 válido.
  - **Cambio de criterio (2026-10-09):** la tarjeta aparece SIEMPRE que `opening_balance_cents` sea null,
    sin importar el balance (antes: solo si balance ≤ 0). Sin saldo inicial el runway puede verse bien y
    aun así no reflejar la plata real (ej.: S/ 500 sin registrar + 800 de ingreso − 200 de gasto da +600,
    pero el saldo real es 1,100). La X la oculta hasta reiniciar la app (estado en memoria).

## 1c — Presupuesto + Insights (skills: design-taste-frontend + dataviz)
- [ ] Pantalla de Presupuesto (solo stable)
- [ ] Insights: donut, línea de runway, mejor/peor mes, racha (umbral congelado), frases
- [ ] Tarjeta de techos sugeridos (survival)
### Checkpoint 1c — code-review + security-review

## Roadmap pendiente de revisión (al cerrar 1b)
Funciones de la app vieja que NO entran al MVP. Están asignadas a una fase o descartadas por diseño;
revisar juntas al terminar 1b, antes de 1c.
- Captura de notificaciones (Yape, BCP, Agora, Lemon Cash): Fase 4, código archivado en `lib/features/capture/`.
- IA (Gemini/Groq, chat "CFO"): borrada (tag `v1-supabase`).
- Módulo pareja / splits: borrado (tag `v1-supabase`).
- Ciclos de cobro y recordatorio de facturas: borrados (tag `v1-supabase`).
- Cuentas múltiples: hoy solo `entries.account_label` (texto libre); tabla `accounts` diferida a Fase 3.
- Gamificación / logros: borrada (tag `v1-supabase`).
- Biometría / bloqueo de app (`local_auth`): quitada en 1a; recuperable del tag.

