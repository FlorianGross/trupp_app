import 'package:flutter/material.dart';

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
  late int _currentIndex = _safeIndex(widget.initialIndex);
  final Map<String, Widget> _tabCache = {};

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

  static const List<_TabSpec> _tabs = [
    _statusTab,
    _karteTab,
    _verlaufTab,
    _mehrTab,
  ];

  int _safeIndex(int i) {
    final max = _tabs.length - 1;
    if (i < 0) return 0;
    if (i > max) return max;
    return i;
  }

  Widget _buildTab(_TabSpec spec) {
    return _tabCache.putIfAbsent(spec.label, () {
      if (identical(spec, _statusTab)) return const StatusOverview();
      if (identical(spec, _karteTab)) return const MapScreen();
      if (identical(spec, _verlaufTab)) return const StatusHistoryScreen();
      if (identical(spec, _mehrTab)) return const MoreScreen();
      return const SizedBox.shrink();
    });
  }

  void _onTap(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _safeIndex(_currentIndex);
    final currentSpec = _tabs[currentIndex];

    // Sicherstellen, dass der aktuelle Tab gebaut ist
    _buildTab(currentSpec);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _tabs
            .map((t) => _tabCache[t.label] ?? const SizedBox.shrink())
            .toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: _onTap,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        showUnselectedLabels: true,
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  activeIcon: Icon(t.activeIcon),
                  label: t.label,
                ))
            .toList(),
      ),
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
