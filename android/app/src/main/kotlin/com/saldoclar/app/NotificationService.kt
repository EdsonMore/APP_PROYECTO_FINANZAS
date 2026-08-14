package com.saldoclar.app

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Servicio en segundo plano que escucha las notificaciones de las aplicaciones
 * financieras soportadas y reenvía los datos relevantes a Flutter mediante un
 * EventChannel (Platform Channels).
 *
 * Robustez:
 *  - Si Flutter no está escuchando (app cerrada), los eventos se encolan en memoria
 *    y en SharedPreferences para no perderlos.
 *  - Al reconectarse el EventChannel se vacía la cola pendiente.
 */
class NotificationService : NotificationListenerService() {

    companion object {
        private const val TAG = "SaldoClaro"
        const val CHANNEL = "saldo_claro/notifications"

        // Conjunto de packages de aplicaciones financieras soportadas.
        // Incluye las apps base (Yape, BCP, Agora, Lemon) y las apps que el
        // usuario puede mapear desde "Reconocimiento de apps" (Interbank,
        // BBVA, Plin, etc.). Para apps adicionales, añade su package aquí o
        // usa la captura de prueba para mapearla.
        //
        // Nota de producción: Sip/Agora puede reportarse como
        // "pe.agora.app" o "com.agora.app"; se escuchan ambas variantes.
        val SUPPORTED_PACKAGES = setOf(
            "com.bcp.innovacxion.yapeApp", // Yape
            "com.bcp.bank.bcp",            // BCP
            "pe.agora.app",                // Agora (Movistar Money)
            "com.agora.app",               // Sip / Agora (variante)
            "com.lemon.lemoncash",          // Lemon Cash
            "com.interbank.bond",           // Interbank
            "pe.com.bbva.bbvacontigo",      // BBVA
            "pe.plin.app",                  // Plin
            "pe.gob.bn.android",            // Banco de la Nación
            "pe.com.scotiabank",            // Scotiabank
            "com.banbif.mobileapp"          // BanBif
        )

        private const val PREFS_NAME = "saldo_claro_notifications"
        private const val KEY_QUEUE = "pending_queue"
        private const val KEY_MAPPED = "mapped_packages"

        // Instancia actual del servicio (puede ser null si aún no se crea).
        var instance: NotificationService? = null
            private set

        // Sink activo de Flutter (null si Flutter no escucha).
        private var eventSink: EventChannel.EventSink? = null

        // Cola en memoria de notificaciones pendientes de entregar a Flutter.
        private val pendingQueue = ArrayDeque<Map<String, Any>>()

        // Packages que el usuario mapeó desde "Reconocimiento de apps". Se
        // persisten en SharedPreferences para que el servicio los siga
        // escuchando aunque la app se reinicie.
        private val mappedPackages = mutableSetOf<String>()

        // Modo "capturar TODO" activado solo mientras el usuario usa
        // "Reconocimiento de apps": permite ver notificaciones de apps que aún
        // no están en la lista base para mapearlas. Es en memoria: se reinicia
        // solo al reiniciar el servicio (máxima privacidad por defecto).
        var captureAll: Boolean = false
            private set

        /**
         * Activa/desactiva el modo de captura total (para el mapeo de apps).
         * Mientras esté activo se reenvían notificaciones de CUALQUIER app.
         */
        @Synchronized
        fun setCaptureAll(enabled: Boolean) {
            captureAll = enabled
            Log.d(TAG, "captureAll=$enabled")
        }

        /**
         * Registra un package que el usuario mapeó y lo persiste para que el
         * servicio lo siga escuchando en el futuro.
         */
        @Synchronized
        fun addMappedPackage(packageName: String) {
            if (packageName.isBlank()) return
            mappedPackages.add(packageName)
            instance?.persistMappedPackages()
            Log.d(TAG, "Package mapeado agregado: $packageName")
        }

        fun isSupported(packageName: String): Boolean =
            packageName in SUPPORTED_PACKAGES || packageName in mappedPackages

        /**
         * Configura el EventChannel (llamado desde MainActivity).
         */
        fun configureChannel(messenger: BinaryMessenger) {
            EventChannel(messenger, CHANNEL).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        Log.d(TAG, "EventChannel escuchando. Flush de pendientes...")
                        flushPending()
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                        Log.d(TAG, "EventChannel cancelado.")
                    }
                }
            )
        }

        /**
         * Envía un evento a Flutter. Si no hay sink, lo encola.
         */
        private fun sendToFlutter(payload: Map<String, Any>) {
            val sink = eventSink
            if (sink != null) {
                try {
                    sink.success(payload)
                } catch (e: Exception) {
                    Log.e(TAG, "Error enviando a Flutter: ${e.message}")
                    pendingQueue.add(payload)
                }
            } else {
                pendingQueue.add(payload)
                Log.d(TAG, "Flutter no escucha. Evento encolado (${pendingQueue.size}).")
            }
        }

        /**
         * Vuelca la cola pendiente hacia Flutter y limpia el persistido.
         */
        private fun flushPending() {
            val sink = eventSink ?: return
            while (pendingQueue.isNotEmpty()) {
                try {
                    sink.success(pendingQueue.removeFirst())
                } catch (e: Exception) {
                    Log.e(TAG, "Error drenando cola: ${e.message}")
                    break
                }
            }
            instance?.persistQueue()
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        loadPersistedQueue()
        loadMappedPackages()
        Log.d(TAG, "NotificationService creado. Cola persistida cargada: ${pendingQueue.size}")
    }

    override fun onDestroy() {
        persistQueue()
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListenerService conectado.")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        persistQueue()
        Log.d(TAG, "NotificationListenerService desconectado.")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        // Log de depuración: se imprime para TODA notificación que captura el
        // listener. Ver en consola con: adb logcat -s DEBUG_NOTIF
        Log.d("DEBUG_NOTIF", "Notificación detectada: ${sbn.packageName}")

        val packageName = sbn.packageName ?: return
        // Solo procesamos notificaciones de las apps financieras configuradas
        // o de apps que el usuario haya mapeado. Durante el mapeo activo
        // (captureAll) se reenvía cualquier app para poder descubrir su package.
        if (packageName !in SUPPORTED_PACKAGES && !captureAll && packageName !in mappedPackages) return

        val notification: Notification = sbn.notification ?: return
        val extras: Bundle = notification.extras ?: return

        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getString(Notification.EXTRA_TEXT) ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        if (title.isBlank() && text.isBlank() && bigText.isBlank()) return

        val timestamp = sbn.postTime

        val payload = mapOf<String, Any>(
            "title" to title,
            "text" to text.ifBlank { bigText },
            "packageName" to packageName,
            "timestamp" to timestamp
        )

        Log.d(TAG, "Notificación capturada: $payload")

        sendToFlutter(payload)
        persistQueue()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
    }

    // ------------------------------------------------------------------
    // Persistencia local (SharedPreferences) para no perder eventos.
    // ------------------------------------------------------------------

    private fun getPrefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun loadPersistedQueue() {
        if (pendingQueue.isNotEmpty()) return
        val raw = getPrefs().getString(KEY_QUEUE, null) ?: return
        try {
            val stored = raw.split("||")
            for (entry in stored) {
                if (entry.isBlank()) continue
                val parts = entry.split("@@", limit = 4)
                if (parts.size == 4) {
                    val timestamp = parts[3].toLongOrNull() ?: System.currentTimeMillis()
                    pendingQueue.add(
                        mapOf<String, Any>(
                            "title" to parts[0],
                            "text" to parts[1],
                            "packageName" to parts[2],
                            "timestamp" to timestamp
                        )
                    )
                }
            }
            Log.d(TAG, "Cargadas ${pendingQueue.size} notificaciones persistidas.")
        } catch (e: Exception) {
            Log.e(TAG, "Error cargando cola persistida: ${e.message}")
        }
    }

    private fun persistQueue() {
        if (pendingQueue.isEmpty()) return
        val sb = StringBuilder()
        for (payload in pendingQueue) {
            sb.append(payload["title"]).append("@@")
                .append(payload["text"]).append("@@")
                .append(payload["packageName"]).append("@@")
                .append(payload["timestamp"]).append("||")
        }
        getPrefs().edit().putString(KEY_QUEUE, sb.toString()).apply()
    }

    // ------------------------------------------------------------------
    // Persistencia de packages mapeados por el usuario.
    // ------------------------------------------------------------------

    private fun loadMappedPackages() {
        if (mappedPackages.isNotEmpty()) return
        val raw = getPrefs().getString(KEY_MAPPED, null) ?: return
        val stored = raw.split("|").filter { it.isNotBlank() }
        mappedPackages.addAll(stored)
        Log.d(TAG, "Cargados ${mappedPackages.size} packages mapeados.")
    }

    private fun persistMappedPackages() {
        if (mappedPackages.isEmpty()) return
        getPrefs().edit().putString(KEY_MAPPED, mappedPackages.joinToString("|")).apply()
    }
}
