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
 * IOT Screen – scrollbare Liste mit Status-Buttons (1–9).
 * ListTemplate statt GridTemplate wegen fehlender Item-Limitierung.
 */
class TruppIotScreen(carContext: CarContext) : Screen(carContext) {

    private val prefs: SharedPreferences = carContext.getSharedPreferences(
        "FlutterSharedPreferences",
        Context.MODE_PRIVATE
    )
    private val client = OkHttpClient()

    // Statusliste in BOS-Reihenfolge (ohne Status 0 / Notruftaste)
    private val statusList = listOf(
        StatusInfo(1, "Einsatzbereit Funk"),
        StatusInfo(2, "Einsatzbereit Wache"),
        StatusInfo(3, "Auftrag angenommen"),
        StatusInfo(4, "Ziel erreicht"),
        StatusInfo(5, "Sprechwunsch"),
        StatusInfo(6, "Nicht einsatzbereit"),
        StatusInfo(7, "Transport"),
        StatusInfo(8, "Ziel KH / Ankunft"),
        StatusInfo(9, "Sonstiges"),
    )

    private var currentStatus: Int = 1
    private var connectionOk: Boolean? = null   // null = unbekannt, true = OK, false = Fehler

    init {
        loadCurrentStatus()
    }

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()

        statusList.forEach { info ->
            val isActive = info.num == currentStatus
            listBuilder.addItem(
                Row.Builder()
                    .setTitle("Status ${info.num}")
                    .addText(info.text)
                    .setOnClickListener { sendStatus(info.num) }
                    .setImage(
                        CarIcon.Builder(
                            androidx.core.graphics.drawable.IconCompat.createWithResource(
                                carContext,
                                if (isActive) android.R.drawable.radiobutton_on_background
                                else android.R.drawable.radiobutton_off_background
                            )
                        ).build()
                    )
                    .build()
            )
        }

        val connIndicator = when (connectionOk) {
            true  -> "● Verbunden"
            false -> "✗ Fehler"
            null  -> "○"
        }

        return ListTemplate.Builder()
            .setTitle("Trupp Status $connIndicator")
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(listBuilder.build())
            .build()
    }

    fun updateStatus(status: Int) {
        if (statusList.any { it.num == status }) {
            currentStatus = status
            invalidate()
        }
    }

    private fun sendStatus(status: Int) {
        val protocol = prefs.getString("flutter.protocol", null) ?: "https"
        val server   = prefs.getString("flutter.server", null) ?: ""
        val token    = prefs.getString("flutter.token", null) ?: ""
        val issi     = prefs.getString("flutter.issi", null) ?: ""

        if (server.isEmpty() || token.isEmpty() || issi.isEmpty()) {
            connectionOk = false
            invalidate()
            return
        }

        val url = "$protocol://$server/$token/setstatus?issi=$issi&status=$status"
        val request = Request.Builder().url(url).get().build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                connectionOk = false
                invalidate()
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    connectionOk = it.isSuccessful
                    if (it.isSuccessful) {
                        currentStatus = status
                        saveCurrentStatus(status)
                        // Broadcast an Flutter-App senden
                        val intent = Intent("dev.floriang.trupp_app.STATUS_CHANGED")
                        intent.putExtra("status", status)
                        carContext.sendBroadcast(intent)
                    }
                    invalidate()
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

    data class StatusInfo(val num: Int, val text: String)
}
