# Zusätzliche R8/ProGuard-Keep-Regeln für den Release-Build.
#
# Die Flutter-Gradle-Rules (io.flutter.**) und die Consumer-Rules der Plugins
# werden automatisch eingebunden. Hier nur ergänzende Regeln für Bibliotheken,
# die per Reflection/JNI angesprochen werden oder die R8 sonst als "missing
# class" bemängelt.

# --- Flutter Deferred Components / Play Core -------------------------------
# Flutters Engine referenziert Play-Core-Klassen (Split-Install), die diese App
# nicht nutzt. Ohne dies bricht der R8-Full-Mode mit "Missing classes" ab.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# --- Android Automotive / Car App Library ---------------------------------
# Wird für die IOT-Car-App genutzt und intern teils reflektiv aufgelöst.
-keep class androidx.car.app.** { *; }
-dontwarn androidx.car.app.**

# --- OkHttp / Okio (GPS-/Status-Übertragung) ------------------------------
# Beide bringen eigene Consumer-Rules mit; hier nur Warnungen unterdrücken.
-dontwarn okhttp3.**
-dontwarn okio.**

# --- App-eigener Plattform-Bridge-Code ------------------------------------
# MainActivity/BroadcastReceiver werden über das Manifest bzw. Intents
# angesprochen; explizit halten, damit R8 sie nicht wegoptimiert.
-keep class dev.floriang.trupp_app.trupp_app.** { *; }
