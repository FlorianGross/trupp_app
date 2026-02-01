package dev.floriang.trupp_app.trupp_app

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.*
import okhttp3.*
import android.content.Context
import android.content.SharedPreferences
import android.content.Intent
import java.io.IOException

/**
 * IOT Screen - Grid-ähnliche Liste mit Status-Buttons
 */
class TruppIotScreen(carContext: CarContext) : Screen(carContext) {

    private val prefs: SharedPreferences = carContext.getSharedPreferences(
        "FlutterSharedPreferences",
        Context.MODE_PRIVATE
    )
    private val client = OkHttpClient()

    // Status-Definitionen
    private val statusMap = mapOf(
        0 to StatusInfo("Dringend", CarColor.RED),
        1 to StatusInfo("Einsatzbereit Funk", CarColor.GREEN),
        2 to StatusInfo("Wache", CarColor.BLUE),
        3 to StatusInfo("Auftrag Angenommen", CarColor.GREEN),
        4 to StatusInfo("Ziel erreicht", CarColor.YELLOW),
        5 to StatusInfo("Sprechwunsch", CarColor.BLUE),
        6 to StatusInfo("Nicht Einsatzbereit", CarColor.RED),
        7 to StatusInfo("Transport", CarColor.GREEN),
        8 to StatusInfo("Ziel Erreicht", CarColor.YELLOW),
        9 to StatusInfo("Sonstiges", CarColor.BLUE)
    )

    private var currentStatus: Int = 1
    private var lastLocation: String = ""
    private var connectionStatus: String = "○"

    init {
        loadCurrentStatus()
    }

    override fun onGetTemplate(): Template {
        return GridTemplate.Builder().apply {
            setTitle("Trupp Status")
            setHeaderAction(Action.APP_ICON)

            // Action Strip - kompakter Header
            setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("$currentStatus")
                            .setBackgroundColor(statusMap[currentStatus]?.color ?: CarColor.DEFAULT)
                            .build()
                    )
                    .addAction(
                        Action.Builder()
                            .setTitle(connectionStatus)
                            .build()
                    )
                    .build()
            )

            // Grid mit Status-Buttons
            setSingleList(createStatusGrid())

        }.build()
    }

    private fun createStatusGrid(): ItemList {
        val builder = ItemList.Builder()

        // Alle Status als Grid Items
        statusMap.forEach { (num, info) ->
            val isActive = num == currentStatus

            builder.addItem(
                GridItem.Builder()
                    .setTitle(num.toString())
                    .setText(info.text)
                    .setImage(createIcon(info.color, isActive))
                    .setOnClickListener {
                        sendStatus(num)
                    }
                    .build()
            )
        }

        return builder.build()
    }

    private fun createIcon(color: CarColor, isActive: Boolean): CarIcon {
        val iconRes = if (isActive) {
            android.R.drawable.radiobutton_on_background
        } else {
            android.R.drawable.radiobutton_off_background
        }

        return CarIcon.Builder(
            androidx.core.graphics.drawable.IconCompat.createWithResource(
                carContext,
                iconRes
            )
        )
            .setTint(color)
            .build()
    }

    fun updateStatus(status: Int) {
        if (status in statusMap.keys) {
            currentStatus = status
            invalidate()
        }
    }

    private fun sendStatus(status: Int) {
        // Config laden
        val protocol = prefs.getString("flutter.protocol", null) ?: "https"
        val server = prefs.getString("flutter.server", null) ?: ""
        val token = prefs.getString("flutter.token", null) ?: ""
        val issi = prefs.getString("flutter.issi", null) ?: ""

        if (server.isEmpty() || token.isEmpty() || issi.isEmpty()) {
            connectionStatus = "✗"
            invalidate()
            return
        }

        // URL bauen
        val url = "$protocol://$server/$token/setstatus?issi=$issi&status=$status"

        // HTTP Request
        val request = Request.Builder()
            .url(url)
            .get()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                connectionStatus = "✗"
                invalidate()
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (it.isSuccessful) {
                        currentStatus = status
                        connectionStatus = "●"
                        saveCurrentStatus(status)

                        // Broadcast an Flutter App senden
                        val intent = Intent("dev.floriang.trupp_app.STATUS_CHANGED")
                        intent.putExtra("status", status)
                        carContext.sendBroadcast(intent)

                        invalidate()
                    } else {
                        connectionStatus = "✗"
                        invalidate()
                    }
                }
            }
        })
    }

    private fun loadCurrentStatus() {
        currentStatus = prefs.getInt("flutter.lastStatus", 1)
    }

    private fun saveCurrentStatus(status: Int) {
        prefs.edit().putInt("flutter.lastStatus", status).apply()
    }

    data class StatusInfo(val text: String, val color: CarColor)
}