import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trupp_app/foreground_notification.dart';
import 'package:trupp_app/deep_link_handler.dart';
import 'package:trupp_app/service.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';
import 'data/auto_delete_config.dart';
import 'data/duty_end_config.dart';
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

  // Randlose Anzeige (edge-to-edge) für Android 15+ (targetSdk 36 erzwingt sie
  // ohnehin): Die App zeichnet hinter Status- und Navigationsleiste, beide
  // Leisten werden transparent gehalten. Ersetzt das von Android 15 abgelehnte
  // Setzen fester, opaker Leistenfarben — die einzelnen AppBars steuern die
  // Icon-Helligkeit weiterhin pro Screen selbst.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

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

  // Dienstende: war die App zum Dienstende-Zeitpunkt geschlossen, jetzt
  // automatisch abmelden (Übertragung bleibt aus, Einsatz beendet).
  if (await DutyEndConfig.signOffIfDue()) {
    AppLogger.i('main', 'Dienstende erreicht – automatisch abgemeldet');
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

// ── Farbschema ──────────────────────────────────────────────────────────────
// Rote BOS-Marke auf ruhigen, leicht warmen Neutraltönen. Der Dunkelmodus nutzt
// bewusst gestaffelte, warm-neutrale Flächen (Hintergrund → Karte → Container)
// statt der aus dem roten Seed abgeleiteten, ins Violette laufenden Standard-
// Surfaces. Ein gemeinsamer Builder hält beide Modi konsistent.

const _brandSeed = Color(0xFFC62828); // BOS-Rot (red 800)

final ColorScheme _lightScheme = ColorScheme.fromSeed(
  seedColor: _brandSeed,
  brightness: Brightness.light,
).copyWith(
  surface: const Color(0xFFFAF8F7),
  onSurface: const Color(0xFF1A1514),
  surfaceContainerLowest: const Color(0xFFFFFFFF),
  surfaceContainerLow: const Color(0xFFF7F2F0),
  surfaceContainer: const Color(0xFFF2ECEA),
  surfaceContainerHigh: const Color(0xFFECE4E2),
  surfaceContainerHighest: const Color(0xFFE7DEDB),
  onSurfaceVariant: const Color(0xFF6E615D),
  outline: const Color(0xFFAAA09C),
  outlineVariant: const Color(0xFFE0D7D4),
);

final ColorScheme _darkScheme = ColorScheme.fromSeed(
  seedColor: _brandSeed,
  brightness: Brightness.dark,
).copyWith(
  surface: const Color(0xFF141110),
  onSurface: const Color(0xFFF4EEEB),
  surfaceContainerLowest: const Color(0xFF0E0B0A),
  surfaceContainerLow: const Color(0xFF1B1615),
  surfaceContainer: const Color(0xFF201B19),
  surfaceContainerHigh: const Color(0xFF2A2422),
  surfaceContainerHighest: const Color(0xFF352E2B),
  onSurfaceVariant: const Color(0xFFB0A49F),
  outline: const Color(0xFF6E625E),
  outlineVariant: const Color(0xFF3A322F),
);

ThemeData _buildTheme(ColorScheme scheme, BrandColors brand) {
  final isDark = scheme.brightness == Brightness.dark;
  // Marken-AppBar: hell = kräftiges Rot; dunkel = tiefes, entsättigtes Rot
  // (nachts weniger blendend, Marke bleibt erkennbar).
  final appBarBg = isDark ? const Color(0xFF7C1A16) : _brandSeed;
  final radius = BorderRadius.circular(12);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[brand],
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBg,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dividerTheme: DividerThemeData(
        color: scheme.outlineVariant, thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : scheme.outline),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
    ),
  );
}

final _lightTheme = _buildTheme(_lightScheme, BrandColors.light);
final _darkTheme = _buildTheme(_darkScheme, BrandColors.dark);

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
