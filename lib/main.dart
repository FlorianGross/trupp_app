import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:trupp_app/DeepLinkHandler.dart';
import 'package:trupp_app/service.dart';
import 'ConfigScreen.dart';
import 'StatusOverview.dart';
import 'alarm_screen.dart'; // NEU
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:trupp_app/data/edp_api.dart';
import 'alarm_websocket_service.dart'; // NEU

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
  }

  // NEU: Alarm-Service initialisieren
  final alarmService = AlarmWebSocketService();
  final hasAlarmConfig = await alarmService.loadConfiguration();

  // Verbinde automatisch wenn Konfiguration vorhanden
  if (hasAlarmConfig) {
    try {
      await alarmService.connect();
      print('✅ Alarm-Service auto-verbunden');
    } catch (e) {
      print('⚠️ Alarm-Service Auto-Connect fehlgeschlagen: $e');
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
        material: (_, __) => MaterialAppData(theme: ThemeData.light()),
        cupertino: (_, __) => CupertinoAppData(
          theme: CupertinoThemeData(brightness: Brightness.light),
        ),
        // NEU: Home mit TabBar für Status und Alarmierung
        home: hasConfig ? const MainScreen() : const ConfigScreen(),
      ),
    );
  }
}

// NEU: Haupt-Screen mit Tabs für Status und Alarmierung
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _alarmService = AlarmWebSocketService();
  bool _hasNewAlarm = false;

  @override
  void initState() {
    super.initState();
    _setupAlarmListener();
  }

  void _setupAlarmListener() {
    // Höre auf neue Alarmierungen für Badge
    _alarmService.alarmStream.listen((alarm) {
      if (mounted && _currentIndex != 1) {
        setState(() {
          _hasNewAlarm = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          StatusOverview(), // Dein bestehender Status-Screen
          AlarmScreen(),     // NEU: Alarmierungs-Screen
        ],
      ),
      bottomNavBar: PlatformNavBar(
        currentIndex: _currentIndex,
        itemChanged: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 1) {
              _hasNewAlarm = false; // Badge zurücksetzen
            }
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.radio_button_checked),
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.emergency),
                if (_hasNewAlarm)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 8,
                        minHeight: 8,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Alarm',
          ),
        ],
      ),
    );
  }
}