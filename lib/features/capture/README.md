# Captura de notificaciones — Fase 4 experimental

**Estado: desconectado del arranque.** Nada de esta carpeta se importa desde
`lib/main.dart`, así que no entra al APK de la Fase 1. Se conserva escrito y
testeado para reactivarlo en la Fase 4.

## Qué hay

| Pieza | Ruta | Estado |
|---|---|---|
| Servicio Android | `android/app/src/main/kotlin/com/saldoclar/app/NotificationService.kt` | Intacto. **No declarado** en `AndroidManifest.xml` |
| Puente Kotlin → Dart | `lib/core/notification/notification_listener_channel.dart` | Intacto |
| Orquestador | `lib/features/capture/service/notification_capture_service.dart` | Intacto, imports rotos (ver abajo) |
| Parser | `lib/core/utils/regex_parser.dart` | Intacto, **tests verdes** |
| Redactor OTP | `lib/core/utils/notification_redactor.dart` | Intacto, **tests verdes** |
| Categorizador | `lib/core/services/rule_categorizer.dart` (tests verdes), `smart_categorizer.dart` | Intactos |
| Permisos | `lib/core/permissions/`, `lib/features/permissions/`, `dashboard/.../app_recognition_screen.dart` | Intactos |

Tests que siguen corriendo: `test/features/capture/`, `test/widget_test.dart`
(parser) y `test/services_test.dart`.

## Por qué no compila hoy (y no importa)

El orquestador y `smart_categorizer` importan repositorios Supabase,
`billing_cycles` y `ai_service`. Los dos últimos se borraron (están en el tag
`v1-supabase`) y Supabase salió del `pubspec`. Estos archivos están excluidos
en `analysis_options.yaml`.

`MainActivity.kt` todavía configura el `EventChannel`: no hace nada mientras el
servicio no esté declarado en el manifest.

## Para reactivar (Fase 4)

1. Volver a declarar `<service android:name=".NotificationService" ...>` y el
   permiso `BIND_NOTIFICATION_LISTENER_SERVICE` en el manifest. Ver el diff del
   tag `v1-supabase`. Hacerlo **solo en un flavor `capture`** fuera de Play
   público.
2. Reescribir el orquestador para que inserte en la tabla drift `entries` con
   `origin = 'auto'`, en lugar de los repositorios Supabase.
3. Mantener `NotificationRedactor` antes de cualquier persistencia o log.
4. Sacar estas rutas de `analysis_options.yaml`.
