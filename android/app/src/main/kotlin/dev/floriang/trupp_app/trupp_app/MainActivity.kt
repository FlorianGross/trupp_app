package dev.floriang.trupp_app.trupp_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity mit BroadcastReceiver für IOT Car App Kommunikation
 */
class MainActivity: FlutterActivity() {

    private val CHANNEL = "dev.floriang.trupp_app/status"
    private lateinit var methodChannel: MethodChannel

    // Receiver für Status-Änderungen AUS der IOT Car App
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val status = intent?.getIntExtra("status", -1) ?: return
            if (status >= 0) {
                // Status an Flutter weitergeben
                methodChannel.invokeMethod("statusChanged", mapOf("status" to status))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        // Handler für Calls VON Flutter
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendStatusToIot" -> {
                    val status = call.argument<Int>("status") ?: -1
                    if (status >= 0) {
                        // Broadcast an IOT Car App senden
                        val intent = Intent("dev.floriang.trupp_app.STATUS_UPDATE")
                        intent.putExtra("status", status)
                        sendBroadcast(intent)
                        result.success(true)
                    } else {
                        result.error("INVALID_STATUS", "Status must be 0-9", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Receiver für Status-Updates AUS der IOT App registrieren
        registerReceiver(
            statusReceiver,
            IntentFilter("dev.floriang.trupp_app.STATUS_CHANGED"),
            RECEIVER_NOT_EXPORTED
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(statusReceiver)
        } catch (e: Exception) {
            // Receiver war nicht registriert
        }
    }
}