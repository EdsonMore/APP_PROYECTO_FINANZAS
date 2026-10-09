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

### Checkpoint 1a — revisión humana ✅

## 1b — Pantallas núcleo ✅ (`fase-1b-completa`)
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
- [x] Contexto bajo el runway (`fase-1b-runway-context`)
- [x] Ajustes: modo, nombre, saldo inicial, ventana de runway, catálogos, CSV (`fase-1b-ajustes`)
### Checkpoint 1b ✅ — 318 tests, capturas en `docs/screenshots/fase-1b-*`

## Para 1c o 2
- [ ] Tocar un movimiento → editarlo. Deslizarlo → borrarlo.
- [ ] Semáforo: comparar el mes actual con el anterior ("12 % más que septiembre"). Solo con al menos 2 meses de datos.
- [x] Tarjeta "¿Cuánto tienes hoy?" en el Home + hoja de saldo inicial (`fase-1b-saldo`). S/ 0 válido.
  - **Cambio de criterio (2026-10-09):** la tarjeta aparece SIEMPRE que `opening_balance_cents` sea null,
    sin importar el balance (antes: solo si balance ≤ 0). Sin saldo inicial el runway puede verse bien y
    aun así no reflejar la plata real (ej.: S/ 500 sin registrar + 800 de ingreso − 200 de gasto da +600,
    pero el saldo real es 1,100). La X la oculta hasta reiniciar la app (estado en memoria).

## 1c — Presupuesto + Insights ⏭ siguiente (skills: design-taste-frontend + dataviz)
Arranca como siempre: ficha + wireframes antes de código. Antes de 1c, revisar el "Roadmap pendiente".
- [ ] Pantalla de Presupuesto (solo Estable): techos por categoría editables (`budgets`), sugeridos por histórico (`suggestedCaps`)
- [ ] Insights: donut de gastos 30 días, línea de runway (60 días), mejor/peor mes de ingreso, racha (umbral congelado), frases
- [ ] Tarjeta de techos sugeridos dentro de Insights (solo Supervivencia)
- [ ] Paleta de colores por categoría con `dataviz` (hoy los ítems nuevos usan el neutro `#525252`)
- [ ] Revisar con el usuario: "Ingreso típico 30d" (normalizado) junto a "Entró S/ X" (real) puede confundir
### Checkpoint 1c — code-review + security-review

## Roadmap pendiente de revisión (al cerrar 1b) — ✅ revisado el 2026-10-09, ver "Roadmap revisado" al final
Funciones de la app vieja que NO entran al MVP. Están asignadas a una fase o descartadas por diseño;
revisar juntas al terminar 1b, antes de 1c.
- Captura de notificaciones (Yape, BCP, Agora, Lemon Cash): Fase 4, código archivado en `lib/features/capture/`.
- IA (Gemini/Groq, chat "CFO"): borrada (tag `v1-supabase`).
- Módulo pareja / splits: borrado (tag `v1-supabase`).
- Ciclos de cobro y recordatorio de facturas: borrados (tag `v1-supabase`).
- Cuentas múltiples: hoy solo `entries.account_label` (texto libre); tabla `accounts` diferida a Fase 3.
- Gamificación / logros: borrada (tag `v1-supabase`).
- Biometría / bloqueo de app (`local_auth`): quitada en 1a; recuperable del tag.


## Feedback del día de uso (2026-10-09)

### Fixes pequeños aplicados
- [x] Aceptar emojis en el nombre del espacio (`fase-1b-fix-emoji`)
- [x] Cambiar el ícono de "Otros" a `category` (`fase-1b-fix-icono-otros`)

### Mejoras para 1c
- [ ] Saldo actual debajo del número principal, en todos los modos
      ("Saldo actual: S/ 1,100"). El runway mide viabilidad; el saldo
      mide liquidez. Ambos importan.
- [ ] Ícono de info al lado del runway que explique la fórmula:
      "Calculado con tu saldo actual y tu gasto promedio de los últimos
      14 días."
- [ ] Verificar que cada modo tenga un texto de contexto diferente en el
      Home, para que el usuario entienda por qué el número cambia.
- [ ] Toggle manual de modo oscuro en Ajustes (independiente del
      sistema).

### Roadmap posterior
- [ ] **Multi-cuenta** (Fase 3): tabla `accounts`, asignación de cada
      movimiento, cálculo por cuenta. Hoy `account_label` es texto libre.
- [ ] **Recordatorios de facturas** (Fase 4/5): fechas recurrentes,
      notificaciones push, gestión de pagos.
- [ ] **IA chatbot** (heurísticas en 1c/2, IA real en 5+):
      - En 1c/2: "insight del día" con reglas heurísticas (frases tipo
        "Llevas 12 días gastando menos de lo que entra"). Sin IA.
      - En 5+: chatbot real con backend (Edge Function) para no exponer
        API keys.
- [ ] **Perfil de usuario** (Fase 3, cuando entra login).

### Ya resuelto (confirmar)
- Modo oscuro: funciona con el sistema. El usuario puede activar modo
  oscuro en Ajustes de Android y la app se adapta. (Confirmado: `themeMode`
  sigue al sistema; verificado en el emulador con `cmd uimode night yes/no`
  en Onboarding, Home, registro, saldo y Ajustes.)

### Roadmap revisado (2026-10-09)

Decisiones finales después de revisar con el usuario:

- **Captura de notificaciones**: Fase 4, con expectativas realistas
  (documentar en README que puede no funcionar en todos los fabricantes).
- **IA**: heurísticas en 1c/2, chatbot real en Fase 5+. Las API keys
  gratis van SIEMPRE detrás de un backend proxy, nunca en el APK.
- **Biometría**: Fase 3+ (después de usuarios).
- **Multi-cuenta**: prioridad 2, entra en Fase 3. `account_id` opcional
  en `entries` desde antes de 1c para evitar migración.
- **Perfiles / compartir**: no perfiles separados. "Cuenta compartida"
  en Fase 3+.
- **Recordatorios de facturas**: Fase 4 como "gasto recurrente"
  (2-3 días de trabajo, no semanas).
- **Gamificación**: descartada definitivamente.

#### Detalle por tema
- [ ] **Captura (Fase 4):** al hacerla, documentar en README.md que puede no
      funcionar en todos los fabricantes (cada uno mata el servicio distinto,
      Android 14+ restringe, y los textos de Yape/BCP/Agora cambian cada 2-3
      meses) y que requiere configuración especial. Si no funciona en el
      celular del usuario, es honesto descartarla y dejar la app manual.
- [ ] **IA (Fase 5+):** las API keys (Gemini/Groq, aunque sean gratis) NO van
      en el APK: se extraen decompilándolo y el proveedor puede banear la
      cuenta por abuso. El chatbot real pasa por un backend proxy (Edge
      Function de Supabase) que agrega la key del lado del servidor.
      Mientras tanto: "insight del día" con heurísticas pre-escritas, sin IA
      ni costo.
- [ ] **Multi-cuenta (Fase 3):** tabla `accounts`, `entries.account_id` FK
      opcional, saldo por cuenta (Yape, BCP, crédito, efectivo). Mientras
      tanto, `account_label` es texto libre.
  - [ ] Si se decide agregar `account_id` en 1c, hacerlo ANTES de la
        pantalla de Presupuesto, para no tocar migraciones después.
        (Pendiente de decisión del usuario.)
- [ ] **Cuenta compartida (Fase 3+):** un dueño invita a otro usuario a ver
      y registrar movimientos de ciertas categorías. No son perfiles
      separados. En Fase 1: 1 usuario, 1 dispositivo.
- [ ] **Gasto recurrente (Fase 4):** en el registro, un toggle "Repetir cada
      mes / cada semana / cada año"; la app calcula la próxima fecha y avisa
      3 días antes con una notificación local (`flutter_local_notifications`,
      sin backend). Estimación: 2-3 días.
- Gamificación: descartada definitivamente (no vuelve al roadmap).

