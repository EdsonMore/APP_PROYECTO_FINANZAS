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

## 1c — Presupuesto + Insights ✅ completa (tag `fase-1c-completa`, 406 tests)
Arranca como siempre: ficha + wireframes antes de código. Antes de 1c, revisar el "Roadmap pendiente".
- [x] Pantalla de Presupuesto (solo Estable): techos por categoría editables (`budgets`), sugeridos por histórico (`suggestedCaps`)
- [x] Insights: barras de gasto por categoría 30 días (ordenadas por monto; el donut se descartó en 1c), línea de runway (60 días), mejor/peor mes de ingreso, racha (umbral congelado), frases
- [x] Tarjeta de techos sugeridos dentro de Insights (solo Supervivencia)
- [x] Paleta de colores por categoría con `dataviz` (slots `cat:N`, migración v3)
- [x] Revisado: Home e Insights usan los mismos `avgIncome30`/`avgExpense30` (I2); "Entró S/ X" es el monto real
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

#### Historial de movimientos (revisado 2026-10-09)
- En el Home solo se ven los últimos 5 movimientos. Eso es por diseño,
  pero el usuario necesita ver TODOS.
- [ ] **Fase 2 (MVP publicable)**: pantalla "Historial" con:
  - Todos los movimientos, agrupados por mes/día.
  - Scroll infinito o paginación.
  - Filtro por tipo (gastos / ingresos / todos).
  - Filtro por categoría (chips).
  - Filtro por rango de fecha (este mes, mes pasado, últimos 90 días).
  - Búsqueda por texto en la nota.
  - Estimación: 2-3 días.
- [ ] **Fase 3+ (avanzado)**: edición inline y swipe-to-delete.
- Razón de posponer: 1c ya tiene Presupuesto + Insights. Meter historial
  la alarga. Y el historial necesita diseño propio (filtros, búsqueda,
  agrupación).

### Fase 2 o 3
- [ ] Importador de CSV (para el respaldo del usuario).
      Razón: sin importador, el CSV es solo un backup visual (Excel),
      no una vía de recuperación. El usuario no puede reimportar en
      la app.
      Estimación: 1-2 días.

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


## Revisión post-1c
- [ ] suggestedCaps: cap el sugerido a gasto_real × 1.2. Hoy, con poco
      historial (26 días de 30), sugiere S/ 810 cuando el usuario gastó
      S/ 700. Se siente como "gasta más". Cambio de 1 línea + test.

## Feedback del día de uso (2026-10-12)

### Comentarios del usuario
1. Faltan funciones (multicuentas, etc.). → Roadmap, ya anotado.
2. No queda claro cómo funciona cada modo. → Fix de diseño, Fase 2.
3. "Sin colchón" no se entiende. → Fix de copy, Fase 2.
4. IA chatbot (¿puedo gastar X?). → Decidir: calculadora simple en
   Fase 2, IA real en Fase 5.
5. Modo oscuro manual. → Toggle en Ajustes, Fase 2.
6. Sync con Supabase. → Fase 3, ya anotado.

### Acciones para Fase 2

- [x] Explicación de modos:
  - Ícono de info en el header del Home que explica el modo actual.
  - Pantalla nueva "Modos de uso" en Ajustes con los 3 modos y ejemplos.
- [x] Cambiar "Sin colchón" a "Sin reserva" (decidido; el bloque de
  Insights pasa a "Reserva").
- [ ] Toggle de tema en Ajustes: Sistema / Claro / Oscuro.
- [ ] Calculadora "¿Cuánto puedo gastar hoy?": fórmula determinista
  basada en saldo, gasto diario promedio y días que el usuario necesita
  cubrir. Decidir dónde vive (Home, Insights, o pantalla propia).
- [ ] Decidir: IA real (Fase 5) o chatbot con calculadora (Fase 2).

### Roadmap, ya anotado
- Multi-cuenta: Fase 3.
- Supabase sync: Fase 3.
- Historial completo: Fase 2.
- Recordatorios de facturas: Fase 4.
- Captura de notificaciones: Fase 4.
- IA real: Fase 5.

## Pendientes de legal (Fase 2)
- [x] Reemplazar [CONTACTO] por un correo (Fase 3B): `saldoclaro.oficial@gmail.com`, provisional.
- [ ] **Verificar que `saldoclaro.oficial@gmail.com` es el correo real del proyecto.** Si el
      Gmail que se cree es otro, cambiarlo en: `contactEmail` (lib/features/settings/legal_screen.dart),
      assets/legal/*.md y sus copias en docs/play-store/, docs/landing/index.html y
      borrar-cuenta.html, y correr `python docs/landing/generar_legal.py`. Ojo: no publicar la
      landing ni la ficha de Play con un correo que no sea nuestro.

## Antes de la Fase 2C (publicación beta)

Requisitos:
- [ ] Cuenta de Google Play Console (25 USD).
- [ ] Keystore de producción (generado con keytool).
- [ ] 12 testers comprometidos para la beta cerrada.
- [ ] 14 días de beta cerrada (requisito de Google).
- [ ] Landing page publicada (GitHub Pages o Netlify).
- [ ] Feature graphic final (1024×500 PNG).

Antes de publicar:
- [ ] Confirmar el correo de contacto (hoy `saldoclaro.oficial@gmail.com`, provisional) en:
  - assets/legal/privacidad.md
  - assets/legal/terminos.md
  - docs/play-store/politica-privacidad.md
  - docs/play-store/terminos.md
  - docs/landing/privacidad.html
  - docs/landing/terminos.html
  - docs/landing/index.html
- [ ] Verificar que todo el HTML de la landing tenga el email actualizado.
- [ ] Firmar el AAB con el keystore real.
- [ ] Subir a Play Console en canal de prueba cerrada.

## Fase 3B: pendientes del usuario
- [ ] **SMTP propio** en saldoclaro-test y saldoclaro-prod (Authentication → Emails → SMTP
      Settings; con Gmail: smtp.gmail.com, puerto 587, contraseña de aplicación). Sin esto
      Supabase solo manda correos al equipo del proyecto (2 por hora) y nadie recibe el código.
- [ ] Plantillas "Confirm signup" y "Reset Password" con el código: `supabase/plantillas/`.
- [ ] "Confirm email" activado, código de 6 dígitos y contraseña mínima de 6 en ambos proyectos.
- [ ] Correr el test de punta a punta (`test/features/sync/e2e_supabase_test.dart`, hoy en skip):
      quitar el skip y seguir los pasos de su encabezado, contra saldoclaro-test.
- [ ] Probar en el celular: crear cuenta → código → datos en la nube → cerrar sesión → borrar cuenta.

## Fase 3C: pendientes del usuario
- [ ] Con el SMTP listo: probar en dos teléfonos (o emulador + teléfono) con la misma
      cuenta: cargar en uno, ver en el otro; "Unir" y "Usar solo los de la nube".
- [ ] El test de punta a punta sigue en skip (ver Fase 3B).

## Pendientes técnicos
- [ ] Mutation testing completo sobre pull/engine/scheduler/push
      (27 mutantes restantes). Correr en lotes chicos (5-10 por
      vez) para no agotar memoria. Verificar después de cada lote
      que lib/ no quede con un mutante aplicado.
- [ ] Ícono de sync (3D): si en las pruebas el badge se vuelve confuso, considerar
      mostrarlo también con issues(1) (hoy solo con n > 1).

