package com.saldoclar.app

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// local_auth requiere que la Activity sea una FlutterFragmentActivity para usar
// los BiometricPrompt; por eso extendemos FlutterFragmentActivity en lugar de
// FlutterActivity.
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val PERMISSION_CHANNEL = "saldo_claro/permissions"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Configuramos el EventChannel que conecta Kotlin <-> Flutter.
        val messenger: BinaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        NotificationService.configureChannel(messenger)
        configurePermissionChannel(messenger)
    }

    /**
     * Métodos para comprobar y abrir los ajustes del NotificationListenerService.
     */
    private fun configurePermissionChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    result.success(isNotificationAccessGranted())
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "requestRebind" -> {
                    requestListenerRebind()
                    result.success(true)
                }
                "setCaptureAll" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    NotificationService.setCaptureAll(enabled)
                    result.success(true)
                }
                "addAllowedPackage" -> {
                    val pkg = call.arguments as? String ?: ""
                    NotificationService.addMappedPackage(pkg)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Pide al sistema que vuelva a enlazar el NotificationListenerService.
     *
     * Tras un force-stop, actualización de la app o ahorro de batería el
     * sistema puede dejar el servicio sin vincular aunque el permiso siga
     * activo. Llamar requestRebind() fuerza la reconexión sin pedirle nada
     * al usuario. Se invoca al abrir la app si el permiso ya está concedido.
     */
    private fun requestListenerRebind() {
        val cn = ComponentName(this, NotificationService::class.java)
        try {
            // requestRebind() es @SystemApi (oculta) en compileSdk recientes:
            // se invoca por reflexión, que es la vía estándar.
            val method = NotificationService::class.java
                .getMethod("requestRebind", ComponentName::class.java)
            method.invoke(null, cn)
        } catch (e: Exception) {
            // Si falla, se retoma en el siguiente arranque.
        }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val cn = ComponentName(this, NotificationService::class.java)
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        if (TextUtils.isEmpty(flat)) return false
        val names = flat.split(":")
        for (name in names) {
            val split = ComponentName.unflattenFromString(name)
            if (split != null && cn.packageName == split.packageName &&
                cn.className == split.className
            ) {
                return true
            }
        }
        return false
    }

    private fun openNotificationSettings() {
        val intent = Intent(
            Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
        )
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback: abrir los ajustes de la app.
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            startActivity(fallback)
        }
    }
}
