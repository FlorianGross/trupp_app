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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService();

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

class MyApp extends StatelessWidget {
  final bool hasConfig;

  const MyApp({super.key, required this.hasConfig});

  @override
  Widget build(BuildContext context) {
    return DeepLinkHandler(
      navigatorKey: navigatorKey,
      child: PlatformApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        material: (_, __) => MaterialAppData(
          theme: ThemeData.light(),
        ),
        cupertino: (_, __) => CupertinoAppData(
          theme: const CupertinoThemeData(brightness: Brightness.light),
        ),
        home: hasConfig ? const StatusOverview() : const ConfigScreen(),
      ),
    );
  }
}