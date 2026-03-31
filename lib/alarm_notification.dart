// lib/alarm_notification.dart
//
// Verwaltet lokale Alarmbenachrichtigungen via flutter_local_notifications.
//
// Android: category=alarm → zeigt über DND/Fokus; fullScreenIntent → über gesperrtem Bildschirm.
// iOS:     timeSensitive → bricht durch Fokus-Modi; critical (falls Entitlement vorhanden) → DND.

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

typedef AlarmTapCallback = void Function(AlarmData alarm);

class AlarmNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static AlarmTapCallback? _onTap;

  /// Einmalig in main() + onStart (background isolate) aufrufen.
  static Future<void> initialize({AlarmTapCallback? onTap}) async {
    _onTap = onTap;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // requestCriticalPermission: iOS erlaubt Critical Alerts nur mit Apple-Entitlement.
    // Die Anfrage schadet nicht – ohne Entitlement wird sie still ignoriert.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    // Alarm-Kanal: Importance.max + Alarm-Kategorie → bricht durch DND auf Android
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      // Alarm-Kanal darf DND umgehen
      bypassDnd: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<bool> show(AlarmData alarm) async {
    final prefs = await SharedPreferences.getInstance();
    final lastKey = prefs.getString(_kLastAlarmKey) ?? '';
    if (lastKey == alarm.deduplicationKey) return false;

    await prefs.setString(_kPendingAlarmJson, alarm.toJsonString());
    await prefs.setString(_kLastAlarmKey, alarm.deduplicationKey);

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      // Über dem Sperrbildschirm anzeigen und Bildschirm einschalten
      fullScreenIntent: true,
      // Kategorie „alarm" → Android erlaubt Anzeige trotz DND/Fokus
      category: AndroidNotificationCategory.alarm,
      ticker: alarm.shortTitle,
      visibility: NotificationVisibility.public,
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
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // timeSensitive bricht durch Focus-Modi (Nicht stören etc.) auf iOS 15+
      // critical würde zusätzlich DND umgehen – benötigt Apple-Entitlement
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

  static Future<AlarmData?> getPendingAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kPendingAlarmJson);
    if (json == null) return null;
    return AlarmData.tryParseJsonString(json);
  }

  static Future<void> clearPendingAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingAlarmJson);
  }

  static void _onNotificationResponse(NotificationResponse response) =>
      _handleResponse(response);

  static void _handleResponse(NotificationResponse response) {
    if (response.actionId == 'navigate') {
      final mapsUrl = response.payload;
      if (mapsUrl != null && mapsUrl.isNotEmpty) {
        launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (_onTap != null) {
      getPendingAlarm().then((alarm) {
        if (alarm != null) _onTap!(alarm);
      });
    }
  }
}

@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) =>
    _onBackgroundNotificationResponse(response);

void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'navigate') {
    final mapsUrl = response.payload;
    if (mapsUrl != null && mapsUrl.isNotEmpty) {
      launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
    }
  }
}
