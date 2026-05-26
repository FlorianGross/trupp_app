import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'alarm_overview_screen.dart';
import 'data/alarm_store.dart';
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
  final Map<int, Widget> _tabCache = {};

  static const _tabs = [
    _TabSpec(
      icon: Icons.radio_button_unchecked,
      activeIcon: Icons.radio_button_checked,
      label: 'Status',
    ),
    _TabSpec(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      label: 'Karte',
    ),
    _TabSpec(
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      label: 'Alarme',
    ),
    _TabSpec(
      icon: Icons.history_outlined,
      activeIcon: Icons.history,
      label: 'Verlauf',
    ),
    _TabSpec(
      icon: Icons.menu,
      activeIcon: Icons.menu,
      label: 'Mehr',
    ),
  ];

  int _alarmUnread = 0;
  StreamSubscription? _alarmEventSub;

  @override
  void initState() {
    super.initState();
    _refreshAlarmBadge();
    _alarmEventSub = FlutterBackgroundService()
        .on('newAlarm')
        .listen((_) => _refreshAlarmBadge());
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

  Widget _buildTab(int index) {
    return _tabCache.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return const StatusOverview();
        case 1:
          return const MapScreen();
        case 2:
          return const AlarmOverviewScreen();
        case 3:
          return const StatusHistoryScreen();
        case 4:
          return const MoreScreen();
        default:
          return const SizedBox.shrink();
      }
    });
  }

  Future<void> _onTap(int index) async {
    // Beim Wechsel zu „Alarme" lokales Badge zurücksetzen
    if (index == 2) {
      await AlarmStore.markAllSeen();
      if (mounted) setState(() => _alarmUnread = 0);
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Sicherstellen, dass der aktuelle Tab gebaut ist
    _buildTab(_currentIndex);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_tabs.length, (i) {
          return _tabCache[i] ?? const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _onTap,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: List.generate(_tabs.length, (i) {
          final t = _tabs[i];
          final icon = Icon(t.icon);
          final activeIcon = Icon(t.activeIcon);
          // Badge nur für „Alarme"-Tab
          final iconWithBadge = i == 2 && _alarmUnread > 0
              ? _badged(icon, _alarmUnread)
              : icon;
          final activeIconWithBadge = i == 2 && _alarmUnread > 0
              ? _badged(activeIcon, _alarmUnread)
              : activeIcon;
          return BottomNavigationBarItem(
            icon: iconWithBadge,
            activeIcon: activeIconWithBadge,
            label: t.label,
          );
        }),
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
