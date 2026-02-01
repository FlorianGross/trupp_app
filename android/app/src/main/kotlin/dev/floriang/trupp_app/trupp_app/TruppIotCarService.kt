package dev.floriang.trupp_app.trupp_app

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter

/**
 * IOT Car App Service - direkt im Auto-System
 * Keine Notifications, nur Status-Buttons
 */
class TruppIotCarService : CarAppService() {  // ← Erbt von CarAppService

    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR  // ← Erlaubt Android Auto
    }

    override fun onCreateSession(): Session {
        return TruppIotSession()  // ← Muss Session zurückgeben
    }
}

/**
 * Session für die IOT App
 */
class TruppIotSession : Session() {

    private lateinit var mainScreen: TruppIotScreen

    override fun onCreateScreen(intent: Intent): Screen {
        mainScreen = TruppIotScreen(carContext)

        // BroadcastReceiver für Status-Updates von Flutter
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val status = intent?.getIntExtra("status", -1) ?: return
                if (status >= 0) {
                    mainScreen.updateStatus(status)
                }
            }
        }

        // Receiver registrieren
        carContext.registerReceiver(
            receiver,
            IntentFilter("dev.floriang.trupp_app.STATUS_UPDATE")
        )

        return mainScreen
    }
}