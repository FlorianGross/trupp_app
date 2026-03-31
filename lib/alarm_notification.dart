// lib/alarm_notification.dart
//
// Verwaltet lokale Alarmbenachrichtigungen via flutter_local_notifications.
//
// Verwendung:
//   1. AlarmNotificationService.initialize() in main() aufrufen.
//   2. AlarmNotificationService.show(alarm) aus dem Hintergrundservice aufrufen.
//   3. onNotificationTap registrieren, um beim Antippen die Detail-Ansicht zu öffnen.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/alarm_model.dart';

const _kChannelId = 'trupp_alarm';
const _kChannelName = 'Alarmierungen';
const _kChannelDesc = 'EDP-Einsatzalarmierungen';
const _kNotificationId = 42;
const _kLastAlarmKey = 'last_alarm_key';
const _kPendingAlarmJson = 'pending_alarm_json';

/// Wird aufgerufen wenn der Nutzer auf die Benachrichtigung (Body) tippt.
/// Registrierung in main() via [AlarmNotificationService.initialize].
typedef AlarmTapCallback = void Function(AlarmData alarm);

class AlarmNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static AlarmTapCallback? _onTap;

  /// Initialisierung – einmalig in main() aufrufen.
  ///
  /// [onTap] wird aufgerufen wenn der Nutzer die Benachrichtigung antippt
  /// (nicht die Aktions-Buttons). Typischerweise Navigation zur Detail-Ansicht.
  static Future<void> initialize({AlarmTapCallback? onTap}) async {
    _onTap = onTap;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    // Android-Kanal anlegen (Importance.max = Heads-Up-Notification)
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Zeigt eine Alarmbenachrichtigung an.
  ///
  /// Prüft Deduplizierung gegen [_kLastAlarmKey] in SharedPreferences,
  /// damit dieselbe Alarmierung nicht mehrfach erscheint.
  /// Gibt [true] zurück wenn der Alarm tatsächlich neu und angezeigt wurde.
  static Future<bool> show(AlarmData alarm) async {
    final prefs = await SharedPreferences.getInstance();
    final lastKey = prefs.getString(_kLastAlarmKey) ?? '';
    if (lastKey == alarm.deduplicationKey) return false;

    // Alarm persistieren damit nach Benachrichtigungs-Tap die Detail-Ansicht
    // auch dann öffnet wenn die App gerade kalt gestartet wird.
    await prefs.setString(_kPendingAlarmJson, alarm.toJsonString());
    await prefs.setString(_kLastAlarmKey, alarm.deduplicationKey);

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ticker: alarm.shortTitle,
      styleInformation: BigTextStyleInformation(
        alarm.notificationBody,
        contentTitle: '🚨 ${alarm.shortTitle}',
        summaryText: 'ENR ${alarm.enr}',
      ),
      actions: [
        const AndroidNotificationAction(
          'navigate',
          'Navigieren',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'open',
          'Details',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
      // Payload = maps-URL, wird von Aktions-Buttons genutzt
      // (weiterleitung erfolgt via onDidReceiveBackgroundNotificationResponse)
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      _kNotificationId,
      '🚨 ${alarm.shortTitle}',
      alarm.notificationBody,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: alarm.mapsUrl,
    );

    return true;
  }

  /// Liest den letzten (ggf. noch offenen) Alarm aus SharedPreferences.
  /// Gibt null zurück wenn kein Alarm gespeichert ist.
  static Future<AlarmData?> getPendingAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kPendingAlarmJson);
    if (json == null) return null;
    return AlarmData.tryParseJsonString(json);
  }

  /// Löscht den gespeicherten ausstehenden Alarm (nach Anzeige in der UI).
  static Future<void> clearPendingAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingAlarmJson);
  }

  // ---------------------------------------------------------------------------
  // Interne Callbacks
  // ---------------------------------------------------------------------------

  /// Aufgerufen wenn App im Vordergrund ist und Nutzer auf Notification tippt.
  static void _onNotificationResponse(NotificationResponse response) {
    _handleResponse(response);
  }

  /// Verarbeitet Notification-Response (Tap oder Aktions-Button).
  static void _handleResponse(NotificationResponse response) {
    if (response.actionId == 'navigate') {
      final mapsUrl = response.payload;
      if (mapsUrl != null && mapsUrl.isNotEmpty) {
        launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
      }
      return;
    }
    // Tap auf Notification-Body oder "Details"-Button → App öffnen + Detail-Ansicht
    if (_onTap != null) {
      getPendingAlarm().then((alarm) {
        if (alarm != null) _onTap!(alarm);
      });
    }
  }
}

/// Hintergrund-Callback für Notification-Actions wenn App beendet ist.
/// Muss als @pragma('vm:entry-point') in einem eigenen top-level-Kontext stehen.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  _onBackgroundNotificationResponse(response);
}

void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'navigate') {
    final mapsUrl = response.payload;
    if (mapsUrl != null && mapsUrl.isNotEmpty) {
      launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
    }
  }
  // "Details"-Button oder Body-Tap startet die App über den normalen App-Start-Flow;
  // main() liest dann getPendingAlarm() aus und zeigt die Detail-Ansicht.
}
