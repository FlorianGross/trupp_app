package dev.floriang.trupp_app.trupp_app

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

class TruppIotCarService : CarAppService() {

    /**
     * Debug-Builds akzeptieren jeden Host (z. B. die Desktop Head Unit beim
     * Testen). Release-Builds nur die von Google gepflegte Liste der echten
     * Android-Auto-/Automotive-Hosts — ALLOW_ALL ist laut Google nur zum
     * Testen gedacht und fällt bei der Car-Review auf.
     */
    override fun createHostValidator(): HostValidator {
        val debuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        return HostValidator.Builder(applicationContext)
            .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
            .build()
    }

    override fun onCreateSession(): Session {
        return TruppIotSession()
    }
}

class TruppIotSession : Session() {

    private lateinit var mainScreen: TruppIotScreen
    private var receiver: BroadcastReceiver? = null

    override fun onCreateScreen(intent: Intent): Screen {
        mainScreen = TruppIotScreen(carContext)

        // BroadcastReceiver für Status-Updates von Flutter registrieren
        val filter = IntentFilter("dev.floriang.trupp_app.STATUS_UPDATE")
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val status = intent?.getIntExtra("status", -1) ?: return
                if (status >= 0) mainScreen.updateStatus(status)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            carContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            carContext.registerReceiver(receiver, filter)
        }

        // Lifecycle-Observer für sauberes Aufräumen nutzen
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                try {
                    receiver?.let { carContext.unregisterReceiver(it) }
                    receiver = null
                } catch (_: Exception) {}
            }
        })

        return mainScreen
    }
}
