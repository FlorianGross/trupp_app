import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trupp_app/alarm_notification.dart';
import 'package:trupp_app/alarm_overview_screen.dart';
import 'package:trupp_app/deep_link_handler.dart';
import 'package:trupp_app/service.dart';
import 'ConfigScreen.dart';
import 'status_overview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trupp_app/data/edp_api.dart';

// Globaler NavigatorKey
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Globaler Theme-Notifier für Dark/Light Mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> _loadThemePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('darkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
}

Future<void> toggleTheme() async {
  final isDark = themeNotifier.value == ThemeMode.dark;
  themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('darkMode', !isDark);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeBackgroundService();
  } catch (_) {
    // Background-Service wird auf dem Simulator nicht unterstützt
  }

  await _loadThemePreference();

  // Benachrichtigungs-Plugin im Haupt-Isolate initialisieren.
  // Tap auf "Details" oder Notification-Body öffnet die Alarm-Übersicht.
  await AlarmNotificationService.initialize(
    onTap: (alarm) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmOverviewScreen(highlightAlarm: alarm),
        ),
      );
    },
  );

  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool('hasConfig') ?? false;

  // EDP-Client bereitstellen (falls möglich)
  if (hasConfig) {
    await EdpApi.initFromPrefs();

    // Hintergrund-Service automatisch starten, damit Standort
    // auch nach App-Neustart sofort im Hintergrund übertragen wird
    try {
      final svc = FlutterBackgroundService();
      if (!await svc.isRunning()) {
        await svc.startService();
        svc.invoke('setTracking', {'enabled': true});
      }
    } catch (_) {
      // Service-Start fehlgeschlagen (z.B. Simulator)
    }
  }

  // Prüfen ob ein Alarm aus einer Notification-Tap geöffnet wurde (Kaltstart)
  final pendingAlarm = await AlarmNotificationService.getPendingAlarm();

  runApp(MyApp(hasConfig: hasConfig, pendingAlarm: pendingAlarm));
}

final _lightTheme = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.red.shade800,
    brightness: Brightness.light,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.red.shade800,
    foregroundColor: Colors.white,
  ),
);

final _darkTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.red.shade800,
    brightness: Brightness.dark,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.red.shade900,
    foregroundColor: Colors.white,
  ),
);

class MyApp extends StatefulWidget {
  final bool hasConfig;
  final AlarmData? pendingAlarm;

  const MyApp({super.key, required this.hasConfig, this.pendingAlarm});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: ggf. Alarm-Übersicht öffnen (Kaltstart via Notification)
    if (widget.pendingAlarm != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AlarmOverviewScreen(highlightAlarm: widget.pendingAlarm),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, themeMode, __) {
        return DeepLinkHandler(
          navigatorKey: navigatorKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: themeMode,
            home: widget.hasConfig ? const StatusOverview() : const ConfigScreen(),
          ),
        );
      },
    );
  }
}
