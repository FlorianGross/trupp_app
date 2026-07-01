import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trupp_app/alarm_notification.dart';
import 'package:trupp_app/alarm_detail_screen.dart';
import 'package:trupp_app/alarm_overlay.dart';
import 'package:trupp_app/deep_link_handler.dart';
import 'package:trupp_app/service.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';
import 'data/alarm_model.dart';
import 'data/profile_store.dart';
import 'data/unit_type_store.dart';
import 'theme/brand_colors.dart';
import 'unit_type_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trupp_app/data/edp_api.dart';
import 'data/app_prefs.dart';
import 'data/app_logger.dart';

// Overlay-Entry-Point hier referenzieren, damit der Dart-Linker ihn nicht entfernt.
// Die eigentliche Funktion liegt in alarm_overlay.dart.
// ignore: unused_element
final _overlayEntryPoint = overlayMain;

// Globaler NavigatorKey
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Globaler Theme-Notifier für Dark/Light Mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> _loadThemePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool(AppPrefsKeys.darkMode) ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
}

Future<void> toggleTheme() async {
  final isDark = themeNotifier.value == ThemeMode.dark;
  themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(AppPrefsKeys.darkMode, !isDark);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [DIAG] Erwartung: main() läuft NUR im Root-/UI-Isolate ("main"). Taucht hier
  // ein anderer Isolate-Name auf, wird main() fälschlich in einem Hintergrund-
  // Isolate ausgeführt (Ursache für "This class should only be used in the main
  // isolate" beim FlutterBackgroundService()-Aufruf weiter unten).
  AppLogger.i('DIAG', 'main() start · isolate=${Isolate.current.debugName}');

  // WICHTIG: Notification-Channels MÜSSEN vor initializeBackgroundService()
  // angelegt sein — das Plugin referenziert die FGS-Channel-ID, legt sie
  // aber nicht selbst an. Reihenfolge umgekehrt zur Intuition.
  await AlarmNotificationService.initialize(
    onTap: (alarm) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmDetailScreen(alarm: alarm),
        ),
      );
    },
  );

  try {
    await initializeBackgroundService();
  } catch (e, st) {
    // Auf dem Simulator nicht unterstützt — auf echten Geräten unerwartet
    AppLogger.w('main', 'Background-Service Init fehlgeschlagen', e);
    if (st.toString().isNotEmpty) AppLogger.e('main', '', null, st);
  }

  await _loadThemePreference();

  // Abgelaufenes temporäres Einsatz-Profil aufräumen (z. B. wenn die App
  // während des Ablaufs geschlossen war): Profil löschen, Standard aktivieren.
  final expiredProfile = await ProfileStore.expireTemporaryIfDue();
  if (expiredProfile != null) {
    AppLogger.i('main',
        'Einsatz-Profil "${expiredProfile.expiredName}" abgelaufen und gelöscht'
        '${expiredProfile.fallback != null ? ' – "${expiredProfile.fallback!.name}" aktiviert' : ''}');
  }

  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool(AppPrefsKeys.hasConfig) ?? false;

  UnitType? unitType;
  if (hasConfig) {
    await EdpApi.initFromPrefs();

    // GPS-Übertragung nach jedem App-Start deaktiviert
    await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);

    // Hintergrund-Service starten, sobald eine (Webhook-)Konfiguration vorliegt.
    // Der Service übernimmt zwei unabhängige Aufgaben:
    //   • Standort-/Status-Übertragung über die Webhook-Schnittstelle
    //   • Alarm-Polling über den EDP-API-Server (nur wenn proApiUrl gesetzt)
    // Der Start wird bewusst NICHT an die EDP-API (proApiUrl) gekoppelt, damit
    // die Standortübertragung unabhängig von der API funktioniert. Das
    // Alarm-Polling schaltet sich in onStart intern nur bei gesetzter proApiUrl
    // zu. GPS wird hier nicht gesendet: transmissionEnabled ist gerade auf false
    // gesetzt, sodass der Service erst nach expliziter Status-Aktivierung sendet.
    // [DIAG] Zeigt, ob die Standort-Voraussetzungen erfüllt sind.
    AppLogger.i(
        'DIAG',
        'Autostart · webhookValid=${await EdpApi.hasValidConfigInPrefs()}'
        ' · webhookHost=${(prefs.getString(AppPrefsKeys.server) ?? '').isNotEmpty}'
        ' · token=${(prefs.getString(AppPrefsKeys.token) ?? '').isNotEmpty}'
        ' · issi=${(prefs.getString(AppPrefsKeys.issi) ?? '').isNotEmpty}'
        ' · proApiUrl=${(prefs.getString(AppPrefsKeys.proApiUrl) ?? '').isNotEmpty}');

    try {
      final svc = FlutterBackgroundService();
      final running = await svc.isRunning();
      AppLogger.i('DIAG', 'Autostart · service.isRunning=$running');
      if (!running) {
        await svc.startService();
      }
    } catch (e, st) {
      AppLogger.e('main', 'Background-Service konnte nicht gestartet werden', e, st);
    }

    unitType = await UnitTypeStore.load();
  }

  final pendingAlarm = await AlarmNotificationService.getPendingAlarm();

  runApp(MyApp(
    hasConfig: hasConfig,
    pendingAlarm: pendingAlarm,
    unitType: unitType,
  ));
}

// Gemeinsame Komponenten-Defaults für beide Themes: Eckenradius 12 und
// Mindesthöhe 48 als Design-Token, statt sie pro Screen zu wiederholen.
// Explizite styleFrom()/shape-Angaben in einzelnen Screens überschreiben
// diese Defaults weiterhin.
final _cardTheme = CardThemeData(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

final _elevatedButtonTheme = ElevatedButtonThemeData(
  style: ElevatedButton.styleFrom(
    minimumSize: const Size(64, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

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
  cardTheme: _cardTheme,
  elevatedButtonTheme: _elevatedButtonTheme,
  extensions: const <ThemeExtension<dynamic>>[BrandColors.light],
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
  cardTheme: _cardTheme,
  elevatedButtonTheme: _elevatedButtonTheme,
  extensions: const <ThemeExtension<dynamic>>[BrandColors.dark],
);

class MyApp extends StatefulWidget {
  final bool hasConfig;
  final AlarmData? pendingAlarm;
  final UnitType? unitType;

  const MyApp({
    super.key,
    required this.hasConfig,
    this.pendingAlarm,
    this.unitType,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    if (widget.pendingAlarm != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AlarmDetailScreen(alarm: widget.pendingAlarm!),
          ),
        );
      });
    }
  }

  Widget _homeScreen() {
    if (!widget.hasConfig) return const OnboardingScreen();
    if (widget.unitType == null) {
      return UnitTypePickerScreen(
        allowBack: false,
        onComplete: () => const HomeShell(),
      );
    }
    return const HomeShell();
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
            home: _homeScreen(),
          ),
        );
      },
    );
  }
}
