/// Configuración central de la aplicación.
///
/// IMPORTANTE: Reemplaza los valores de Supabase con los de tu proyecto.
/// Crea un archivo `lib/core/config/secrets.dart` (ignorado por git) o
/// usa variables de entorno (--dart-define) en entornos productivos.
library;

import 'secrets.dart';

abstract final class AppConfig {
  static const String appName = 'SaldoClaro';

  /// URL del proyecto Supabase (panel: Project Settings -> API).
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://xgecwjkgalulmddgbfqt.supabase.co');

  /// Clave anon/public de Supabase.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWN3amtnYWx1bG1kZGdiZnF0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MDQ0MzAsImV4cCI6MjEwMjA4MDQzMH0.ASJA_WqQ-NH-_cFJtJgBzRFsO81l_0uZa6jFHGnnJd0',
  );

  /// Clave de API de Google Gemini (funcionalidad de IA).
  ///
  /// Se lee por `--dart-define=GEMINI_API_KEY=...`; si no se pasa, se usa la
  /// clave local de `lib/core/config/secrets.dart` (archivo ignorado por git).
  static String get geminiApiKey {
    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return Secrets.geminiApiKey;
  }

  /// URL base de la API de Gemini.
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Modelo de Gemini usado para clasificación y análisis.
  ///
  /// Verificado contra la API en producción el 12/08/2026: los modelos con
  /// versión fija (gemini-1.5-flash / gemini-2.x-flash) ya no están
  /// disponibles en el proyecto GCP de la app (HTTP 404); el alias vivo
  /// "gemini-flash-latest" es el que responde correctamente con la clave "AQ.".
  static const String geminiModel = 'gemini-flash-latest';

  /// Clave de API de Groq (proveedor de respaldo del servicio de IA).
  ///
  /// Se lee por `--dart-define=GROQ_API_KEY=...`; si no se pasa, se usa la
  /// clave local de `lib/core/config/secrets.dart` (archivo ignorado por git).
  static String get groqApiKey {
    const fromEnv = String.fromEnvironment('GROQ_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return Secrets.groqApiKey;
  }

  /// URL base de la API de Groq (compatible con OpenAI).
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';

  /// Modelo de Groq usado como respaldo (open source, gratuito y rápido).
  static const String groqModel = 'llama-3.3-70b-versatile';

  /// Minutos que se reutiliza un insight de IA ya calculado (sin llamar a la
  /// API de nuevo) para no gastar cuota en cada recarga del dashboard.
  static const Duration aiInsightCacheDuration = Duration(minutes: 15);

  /// Mínimo de movimientos del mes para pedirle a la IA un insight.
  static const int aiInsightMinTransactions = 5;

  /// Máximo de gastos "hormiga" a detectar en insights.
  static const int antRecordExpenseThreshold = 15;

  /// Nombre del canal nativo (EventChannel) usado por NotificationListenerService.
  static const String notificationChannel = 'saldo_claro/notifications';

  /// Simbolo monetario usado en la UI.
  static const String currencySymbol = 'S/';

  /// Colores representativos de cada cuenta.
  static const ColorConfig colors = ColorConfig();
}

/// Colores por aplicación/cuenta financiera.
class ColorConfig {
  const ColorConfig();

  static const int yape = 0xFF7B1FA2; // Morado Yape
  static const int bcp = 0xFF002A8F; // Azul BCP
  static const int agora = 0xFFEF3340; // Rojo Agora
  static const int lemon = 0xFF00A859; // Verde Lemon Cash
  static const int accent = 0xFF1B4332;
  static const int background = 0xFF0F1115;
  static const int surface = 0xFF1A1D24;
  static const int surfaceAlt = 0xFF232731;
  static const int textPrimary = 0xFFF5F7FA;
  static const int textSecondary = 0xFF9AA3B2;
  static const int success = 0xFF2ECC71;
  static const int danger = 0xFFE74C3C;
}
