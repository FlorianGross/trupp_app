import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:trupp_app/foreground_notification.dart';
import 'package:trupp_app/deep_link_handler.dart';
import 'package:trupp_app/service.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';
import 'data/auto_delete_config.dart';
import 'data/profile_store.dart';
import 'data/unit_type_store.dart';
import 'theme/brand_colors.dart';
import 'unit_type_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trupp_app/data/edp_api.dart';
import 'data/app_prefs.dart';
import 'data/app_logger.dart';

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

  // WICHTIG: Notification-Channel MUSS vor initializeBackgroundService()
  // angelegt sein — das Plugin referenziert die FGS-Channel-ID, legt sie
  // aber nicht selbst an. Reihenfolge umgekehrt zur Intuition.
  await ForegroundNotificationService.initialize();

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

  // AutoDelete: Ist eine automatische Konfigurations-Löschung fällig (nach
  // X Stunden oder zu einer festgelegten Uhrzeit)? Dann Konfiguration jetzt
  // löschen, bevor hasConfig gelesen wird → App startet in der Einrichtung.
  if (await AutoDeleteConfig.deleteIfDue()) {
    AppLogger.i('main', 'Konfiguration durch AutoDelete gelöscht');
  }

  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool(AppPrefsKeys.hasConfig) ?? false;

  UnitType? unitType;
  if (hasConfig) {
    await EdpApi.initFromPrefs();

    // GPS-Übertragung nach jedem App-Start deaktiviert
    await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);

    // Der Hintergrund-Service wird NICHT mehr beim App-Start gestartet: er
    // dient ausschließlich der Standort-/Status-Übertragung und wird erst
    // bei Bedarf gestartet (Übertragung aktivieren bzw. automatischer
    // Einsatz-Start beim ersten aktiven Status).
    // [DIAG] Zeigt, ob die Standort-Voraussetzungen erfüllt sind.
    AppLogger.i(
        'DIAG',
        'Autostart · webhookValid=${await EdpApi.hasValidConfigInPrefs()}'
        ' · webhookHost=${(prefs.getString(AppPrefsKeys.server) ?? '').isNotEmpty}'
        ' · token=${(prefs.getString(AppPrefsKeys.token) ?? '').isNotEmpty}'
        ' · issi=${(prefs.getString(AppPrefsKeys.issi) ?? '').isNotEmpty}');

    unitType = await UnitTypeStore.load();
  }

  runApp(MyApp(
    hasConfig: hasConfig,
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
  final UnitType? unitType;

  const MyApp({
    super.key,
    required this.hasConfig,
    this.unitType,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
