// lib/foreground_notification.dart
//
// Legt den Notification-Channel für die Foreground-Service-Notification an
// (dauerhaftes Statussymbol in der Statusleiste). Wird vom
// flutter_background_service-Plugin via
// AndroidConfiguration.notificationChannelId referenziert und MUSS vor
// `service.configure()` per `createNotificationChannel` angelegt sein.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Channel-ID für die Foreground-Service-Notification.
const kForegroundChannelId = 'trupp_foreground';
const _kForegroundChannelName = 'Hintergrund-Tracking';
const _kForegroundChannelDesc =
    'Zeigt an, dass die App im Hintergrund GPS-Positionen sendet. '
    'Diese Benachrichtigung ist systembedingt erforderlich.';

/// Initialisiert das Notification-Plugin und legt den Foreground-Service-Channel
/// an. Einmalig in main() und in onStart (Background-Isolate) aufrufen.
class ForegroundNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Foreground-Service-Channel: niedrige Priorität, kein Sound/Vibration —
    // erscheint stumm in der „silent"-Sektion der Statusleiste.
    const fgsChannel = AndroidNotificationChannel(
      kForegroundChannelId,
      _kForegroundChannelName,
      description: _kForegroundChannelDesc,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      showBadge: false,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(fgsChannel);
  }
}
