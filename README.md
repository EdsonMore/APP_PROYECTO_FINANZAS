# SaldoClaro 💳

Aplicación móvil (Flutter/Android) que captura **automáticamente** las notificaciones
de apps financieras peruanas (Yape, BCP, Agora, Lemon Cash) y las persiste en
**Supabase**, para que tengas el control de tus gastos e ingresos sin registrar nada.

## Características

- 📲 **Captura automática**: un `NotificationListenerService` (Kotlin) escucha las
  notificaciones de `com.bcp.innovacxion.yapeApp`, `com.bcp.bank.bcp`,
  `pe.agora.app` y `com.lemon.lemoncash` y las reenvía a Flutter por un `EventChannel`.
- 🔎 **Motor de parseo Regex** (`lib/core/utils/regex_parser.dart`): extrae monto,
  contraparte y tipo de transacción (ingreso/gasto) de cada notificación.
- 🗄️ **Supabase**: Auth + Base de datos (profiles, accounts, categories, transactions)
  con RLS activado y una RPC transaccional que ajusta el balance de la cuenta.
- 📊 **Dashboard**: balance total, tarjetas de cuenta con colores de cada banco,
  gráfico circular de gastos por categoría (`fl_chart`) y movimientos recientes con
  badges `Auto-Capturado` / `Manual`.
- ➕ Registro manual de movimientos.

## Arquitectura

Clean Architecture / Feature-First con Riverpod:

```
lib/
├── core/                    # Capa transversal (reutilizable)
│   ├── config/              # AppConfig (Supabase URL/keys, colores)
│   ├── models/              # Entidades (Account, Category, Transaction, ...)
│   ├── network/             # Cliente Supabase
│   ├── notification/        # Bridge EventChannel (Kotlin -> Flutter)
│   ├── permissions/         # Verificación del permiso de notificaciones
│   ├── providers/           # Providers Riverpod base
│   ├── theme/               # Tema oscuro
│   └── utils/               # RegexParser, Formatters
└── features/
    ├── auth/                # Login/Registro + repositorio
    ├── capture/             # Servicio de captura de notificaciones
    ├── dashboard/           # Repositorios, providers y UI principal
    └── permissions/         # Pantalla de permiso de notificaciones
```

## Configuración

### 1. Supabase

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En **SQL Editor**, ejecuta el script `supabase/schema.sql` (crea tablas, RLS, RPC y triggers).
3. Copia la **URL** y la **anon key** de *Project Settings → API*.

### 2. Flutter

Edita las credenciales en `lib/core/config/app_config.dart`
(la app también admite `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`):

```dart
static const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://TU-PROYECTO.supabase.co');

static const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'TU-ANON-KEY');
```

Instala dependencias y ejecuta:

```bash
flutter pub get
flutter run
```

### 3. Permiso de notificaciones

La primera vez, la app te llevará a **Ajustes → Acceso a notificaciones** para que
concedas el permiso a SaldoClaro. Sin él no se pueden capturar movimientos.

## Notas importantes

- **Privacidad**: las notificaciones se procesan localmente y solo se envían a
  Supabase las transacciones ya clasificadas (monto, contraparte, app, fecha).
- Los **códigos de seguridad de un solo uso (OTP)** que Yape y otras billeteras
  incluyen en la notificación (p. ej. la copia `"[Nombre] te envió un pago por
  S/ X. El código de seguridad es: Y"` con título `"Confirmación de pago"`)
  son redactados por `NotificationRedactor` antes de persistirse, enviarse a la
  IA o escribirse en logs. Nunca se almacenan.
- El patrón de texto de las notificaciones puede variar según la versión de cada
  app; el parser es extensible (`AppRule`/`RuleMatcher`) y tiene un fallback genérico.
- En este repositorio el `NotificationService` encola los eventos mientras la app
  no está abierta y los entrega al reconectarse (sin pérdida de datos).

## Cumplimiento legal (Ley N.º 29733 y Google Play)

La app incluye:

- **Términos y Condiciones y Política de Privacidad** en la propia app
  (`lib/core/legal/legal_content.dart` + pantalla `LegalScreen`), accesibles
  desde el registro, el Perfil y la pantalla de permisos.
- **Consentimiento previo, libre, expreso e informado**: el usuario debe aceptar
  los documentos legales (casilla en el registro y pantalla de consentimiento
  tras iniciar sesión) antes de que la app capture notificaciones. La aceptación
  se registra en `LegalAcceptanceStore`; al cambiar los documentos se sube
  `kCurrentVersion` y se vuelve a pedir.
- **Transparencia del acceso a notificaciones**: el `NotificationListenerService`
  solo procesa las apps financieras de la lista `SUPPORTED_PACKAGES`; el permiso
  se concede/revoca siempre por el usuario desde los Ajustes del sistema.
- **Minimización de datos**: no se recolectan credenciales, PIN, OTP ni números
  de tarjeta.

> Para publicar en Google Play deberás subir el texto de la Política de
> Privacidad (puedes copiarlo desde la pantalla legal de la app) a una URL
> pública y completar la declaración de "Notification Listener Service" en la
> ficha de la aplicación.
