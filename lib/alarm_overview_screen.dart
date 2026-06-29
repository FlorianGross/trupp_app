// lib/alarm_overview_screen.dart
//
// Übersicht aller empfangenen EDP-Alarme (neueste zuerst), nach Tagen
// gruppiert. Einzelner Alarm → AlarmDetailScreen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'alarm_detail_screen.dart';
import 'data/alarm_model.dart';
import 'data/alarm_store.dart';

class AlarmOverviewScreen extends StatefulWidget {
  /// Wenn gesetzt, wird dieser Alarm in der Liste oben hervorgehoben
  /// (z.B. direkt nach Eingang über Notification).
  final AlarmData? highlightAlarm;

  const AlarmOverviewScreen({super.key, this.highlightAlarm});

  @override
  State<AlarmOverviewScreen> createState() => _AlarmOverviewScreenState();
}

class _AlarmOverviewScreenState extends State<AlarmOverviewScreen> {
  List<AlarmData> _alarms = [];
  bool _loading = true;
  StreamSubscription? _newAlarmSub;
  Timer? _relTimeTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Neuen Alarm sofort oben einfügen ohne erneuten Netzwerk-Call
    _newAlarmSub = FlutterBackgroundService().on('newAlarm').listen((data) {
      if (data == null || !mounted) return;
      try {
        final alarm = AlarmData.fromJson(Map<String, dynamic>.from(data));
        if (_alarms.isEmpty ||
            _alarms.first.deduplicationKey != alarm.deduplicationKey) {
          setState(() => _alarms.insert(0, alarm));
        }
      } catch (_) {}
    });
    // Relative Zeitangaben ("vor 5 Min") periodisch aktualisieren.
    _relTimeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _newAlarmSub?.cancel();
    _relTimeTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final alarms = await AlarmStore.getAll();
    if (mounted) setState(() { _alarms = alarms; _loading = false; });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Verlauf löschen'),
        content: const Text('Alle gespeicherten Alarme löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      await AlarmStore.clear();
      if (mounted) setState(() => _alarms = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlightKey = widget.highlightAlarm?.deduplicationKey;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alarmierungen'),
            if (_alarms.isNotEmpty)
              Text(
                _alarms.length == 1 ? '1 Eintrag' : '${_alarms.length} Einträge',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          if (_alarms.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Verlauf löschen',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alarms.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildGroupedList(highlightKey),
                ),
    );
  }

  // Flache Liste mit Tages-Trennern (Header-Strings + Alarme).
  Widget _buildGroupedList(String? highlightKey) {
    final items = <Object>[];
    String? lastLabel;
    for (final a in _alarms) {
      final label = _dayLabel(a.timestamp);
      if (label != lastLabel) {
        items.add(label);
        lastLabel = label;
      }
      items.add(a);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: EdgeInsets.only(left: 4, top: i == 0 ? 4 : 16, bottom: 6),
            child: Text(
              item.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: Colors.grey.shade500,
              ),
            ),
          );
        }
        final alarm = item as AlarmData;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _AlarmCard(
            alarm: alarm,
            isLatest: highlightKey != null &&
                alarm.deduplicationKey == highlightKey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlarmDetailScreen(alarm: alarm),
              ),
            ),
          ),
        );
      },
    );
  }

  String _dayLabel(DateTime? dt) {
    if (dt == null) return 'Unbekannt';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final w = wd[(dt.weekday - 1) % 7];
    return '$w, ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_off_outlined,
                size: 56, color: Colors.red.shade200),
          ),
          const SizedBox(height: 20),
          Text(
            'Keine Alarmierungen',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'Eingehende Einsätze erscheinen hier automatisch.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm-Karte
// ---------------------------------------------------------------------------

class _AlarmCard extends StatelessWidget {
  final AlarmData alarm;
  final bool isLatest;
  final VoidCallback onTap;

  const _AlarmCard({
    required this.alarm,
    required this.isLatest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isLatest ? 4 : 1,
      shadowColor: isLatest ? Colors.red.shade200 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isLatest
            ? BorderSide(color: Colors.red.shade700, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Farb-Akzent links
              Container(width: 5, color: Colors.red.shade700),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconBadge(isLatest: isLatest),
                      const SizedBox(width: 12),
                      Expanded(child: _buildText(context)),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isLatest) ...[
              _Pill(text: 'NEU', color: Colors.red.shade700),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                alarm.shortTitle,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (alarm.hasSondersignal) ...[
              const SizedBox(width: 6),
              _SignalChip(),
            ],
          ],
        ),
        if (alarm.klartext.isNotEmpty && alarm.klartext != alarm.shortTitle) ...[
          const SizedBox(height: 2),
          Text(
            alarm.klartext,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (alarm.address.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  alarm.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            if (alarm.enr.isNotEmpty) ...[
              Icon(Icons.tag, size: 12, color: Colors.grey.shade400),
              const SizedBox(width: 2),
              Text(alarm.enr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(width: 10),
            ],
            Icon(Icons.schedule, size: 12, color: Colors.grey.shade400),
            const SizedBox(width: 3),
            Text(
              _clockTime(alarm.timestamp),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const Spacer(),
            Text(
              alarm.relativeTime,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ],
    );
  }

  String _clockTime(DateTime? dt) {
    if (dt == null) return alarm.ts;
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '$h:$m Uhr';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}. $h:$m';
  }
}

class _IconBadge extends StatelessWidget {
  final bool isLatest;
  const _IconBadge({required this.isLatest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLatest ? Colors.red.shade700 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.campaign,
        size: 24,
        color: isLatest ? Colors.white : Colors.red.shade700,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

/// Kleiner „Blaulicht"-Chip für Sondersignal-Fahrten.
class _SignalChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emergency_share, size: 12, color: Colors.white),
          SizedBox(width: 3),
          Text('Sondersignal',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
