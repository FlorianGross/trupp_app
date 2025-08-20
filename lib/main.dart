import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trupp_app/DeepLinkHandler.dart';
import 'package:trupp_app/service.dart';
import 'ConfigScreen.dart';
import 'StatusOverview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

// ➊ Globaler NavigatorKey
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool('hasConfig') ?? false;

  runApp(MyApp(hasConfig: hasConfig));
}

class MyApp extends StatelessWidget {
  final bool hasConfig;

  const MyApp({super.key, required this.hasConfig});

  @override
  Widget build(BuildContext context) {
    return DeepLinkHandler(
      navigatorKey: navigatorKey, // ➋ Key an Handler geben
      child: PlatformApp(
        debugShowCheckedModeBanner: false,
        // ➌ Key an die App hängen, damit wir überall navigieren können
        navigatorKey: navigatorKey,
        material: (_, __) => MaterialAppData(theme: ThemeData.light()),
        cupertino: (_, __) => CupertinoAppData(
          theme: CupertinoThemeData(brightness: Brightness.light),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => hasConfig ? const StatusOverview() : const ConfigScreen(),
        },
      ),
    );
  }
}
