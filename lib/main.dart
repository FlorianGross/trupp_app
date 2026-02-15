import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trupp_app/deep_link_handler.dart';
import 'package:trupp_app/service.dart';
import 'ConfigScreen.dart';
import 'status_overview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
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
  await initializeBackgroundService();
  await _loadThemePreference();

  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool('hasConfig') ?? false;

  // EDP-Client bereitstellen (falls möglich)
  if (hasConfig) {
    await EdpApi.initFromPrefs();

    // Hintergrund-Service automatisch starten, damit Standort
    // auch nach App-Neustart sofort im Hintergrund übertragen wird
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) {
      await svc.startService();
      svc.invoke('setTracking', {'enabled': true});
    }
  }

  runApp(MyApp(hasConfig: hasConfig));
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

class MyApp extends StatelessWidget {
  final bool hasConfig;

  const MyApp({super.key, required this.hasConfig});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, themeMode, __) {
        final isDark = themeMode == ThemeMode.dark;
        return DeepLinkHandler(
          navigatorKey: navigatorKey,
          child: PlatformApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            material: (_, __) => MaterialAppData(
              theme: _lightTheme,
              darkTheme: _darkTheme,
              themeMode: themeMode,
            ),
            cupertino: (_, __) => CupertinoAppData(
              theme: CupertinoThemeData(
                brightness: isDark ? Brightness.dark : Brightness.light,
                primaryColor: Colors.red.shade800,
              ),
            ),
            home: hasConfig ? const StatusOverview() : const ConfigScreen(),
          ),
        );
      },
    );
  }
}