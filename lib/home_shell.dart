import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_overview_screen.dart';
import 'data/alarm_store.dart';
import 'data/app_prefs.dart';
import 'map_screen.dart';
import 'more_screen.dart';
import 'status_history_screen.dart';
import 'status_overview_screen.dart';

/// Root-Widget mit BottomNavigationBar: ersetzt die Single-Screen-Ansicht
/// mit verstecktem 3-Punkte-Menü. Tabs werden lazy aufgebaut und behalten
/// danach ihren State (IndexedStack).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _currentIndex = widget.initialIndex;
  final Map<String, Widget> _tabCache = {};

  // Wird in initState aus den SharedPreferences geladen. Ohne Alarm-Server
  // (PocketBase-URL) wird der Alarme-Tab ausgeblendet.
  bool _hasAlarmServer = false;
  bool _prefsLoaded = false;

  static const _statusTab = _TabSpec(
    icon: Icons.radio_button_unchecked,
    activeIcon: Icons.radio_button_checked,
    label: 'Status',
  );
  static const _karteTab = _TabSpec(
    icon: Icons.map_outlined,
    activeIcon: Icons.map,
    label: 'Karte',
  );
  static const _alarmeTab = _TabSpec(
    icon: Icons.campaign_outlined,
    activeIcon: Icons.campaign,
    label: 'Alarme',
  );
  static const _verlaufTab = _TabSpec(
    icon: Icons.history_outlined,
    activeIcon: Icons.history,
    label: 'Verlauf',
  );
  static const _mehrTab = _TabSpec(
    icon: Icons.menu,
    activeIcon: Icons.menu,
    label: 'Mehr',
  );

  List<_TabSpec> get _tabs => [
        _statusTab,
        _karteTab,
        if (_hasAlarmServer) _alarmeTab,
        _verlaufTab,
        _mehrTab,
      ];

  int _alarmUnread = 0;
  StreamSubscription? _alarmEventSub;

  @override
  void initState() {
    super.initState();
    _loadAlarmServerFlag();
    _refreshAlarmBadge();
    _alarmEventSub = FlutterBackgroundService()
        .on('newAlarm')
        .listen((_) => _refreshAlarmBadge());
  }

  Future<void> _loadAlarmServerFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final pbUrl = prefs.getString(AppPrefsKeys.pbUrl) ?? '';
    if (!mounted) return;
    setState(() {
      _hasAlarmServer = pbUrl.isNotEmpty;
      _prefsLoaded = true;
      // Falls der initialIndex auf einen ausgeblendeten Tab zeigt, fängt
      // _safeIndex das ab.
      _currentIndex = _safeIndex(_currentIndex);
    });
  }

  int _safeIndex(int i) {
    final max = _tabs.length - 1;
    if (i < 0) return 0;
    if (i > max) return max;
    return i;
  }

  @override
  void dispose() {
    _alarmEventSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlarmBadge() async {
    final count = await AlarmStore.unreadCount();
    if (mounted) setState(() => _alarmUnread = count);
  }

  Widget _buildTab(_TabSpec spec) {
    return _tabCache.putIfAbsent(spec.label, () {
      if (identical(spec, _statusTab)) return const StatusOverview();
      if (identical(spec, _karteTab)) return const MapScreen();
      if (identical(spec, _alarmeTab)) return const AlarmOverviewScreen();
      if (identical(spec, _verlaufTab)) return const StatusHistoryScreen();
      if (identical(spec, _mehrTab)) return const MoreScreen();
      return const SizedBox.shrink();
    });
  }

  Future<void> _onTap(int index) async {
    final spec = _tabs[index];
    // Beim Wechsel zu „Alarme" lokales Badge zurücksetzen
    if (identical(spec, _alarmeTab)) {
      await AlarmStore.markAllSeen();
      if (mounted) setState(() => _alarmUnread = 0);
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Bevor die Prefs gelesen sind, zeigt _tabs nur Status/Karte/Verlauf/Mehr;
    // ein kurzes Flackern beim allerersten Start wäre möglich, also blocken
    // wir das mit einem leeren Scaffold ab.
    if (!_prefsLoaded) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final tabs = _tabs;
    final currentIndex = _safeIndex(_currentIndex);
    final currentSpec = tabs[currentIndex];

    // Sicherstellen, dass der aktuelle Tab gebaut ist
    _buildTab(currentSpec);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: tabs
            .map((t) => _tabCache[t.label] ?? const SizedBox.shrink())
            .toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: _onTap,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: tabs.map((t) {
          final icon = Icon(t.icon);
          final activeIcon = Icon(t.activeIcon);
          final isAlarmTab = identical(t, _alarmeTab);
          final iconWithBadge = isAlarmTab && _alarmUnread > 0
              ? _badged(icon, _alarmUnread)
              : icon;
          final activeIconWithBadge = isAlarmTab && _alarmUnread > 0
              ? _badged(activeIcon, _alarmUnread)
              : activeIcon;
          return BottomNavigationBarItem(
            icon: iconWithBadge,
            activeIcon: activeIconWithBadge,
            label: t.label,
          );
        }).toList(),
      ),
    );
  }

  Widget _badged(Widget icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabSpec {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabSpec(
      {required this.icon, required this.activeIcon, required this.label});
}
