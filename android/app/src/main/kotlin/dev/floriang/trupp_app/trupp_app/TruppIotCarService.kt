package dev.floriang.trupp_app.trupp_app

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build

/**
 * IOT Car App Service - direkt im Auto-System
 * Keine Notifications, nur Status-Buttons
 */
class TruppIotCarService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return TruppIotSession()
    }
}

/**
 * Session für die IOT App
 */
class TruppIotSession : Session() {

    private lateinit var mainScreen: TruppIotScreen
    private var receiver: BroadcastReceiver? = null

    override fun onCreateScreen(intent: Intent): Screen {
        mainScreen = TruppIotScreen(carContext)

        // BroadcastReceiver für Status-Updates von Flutter
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val status = intent?.getIntExtra("status", -1) ?: return
                if (status >= 0) {
                    mainScreen.updateStatus(status)
                }
            }
        }

        // Receiver registrieren (Android 14+ benötigt Export-Flag)
        val filter = IntentFilter("dev.floriang.trupp_app.STATUS_UPDATE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            carContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            carContext.registerReceiver(receiver, filter)
        }

        return mainScreen
    }

    override fun onCarConfigurationChanged(newConfiguration: android.content.res.Configuration) {
        super.onCarConfigurationChanged(newConfiguration)
    }

    fun onDestroy() {
        try {
            receiver?.let { carContext.unregisterReceiver(it) }
        } catch (_: Exception) {}
    }
}
