// lib/alarm_overview_screen.dart
//
// Übersicht aller empfangenen EDP-Alarme (neueste zuerst).
// Einzelner Alarm → AlarmDetailScreen.

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
  }

  @override
  void dispose() {
    _newAlarmSub?.cancel();
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
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Alarmierungen'),
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
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    itemCount: _alarms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _AlarmCard(
                      alarm: _alarms[i],
                      isLatest: i == 0 && widget.highlightAlarm != null &&
                          _alarms[i].deduplicationKey ==
                              widget.highlightAlarm!.deduplicationKey,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AlarmDetailScreen(alarm: _alarms[i]),
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Noch keine Alarmierungen',
            style: TextStyle(fontSize: 17, color: Colors.grey.shade600),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isLatest
            ? BorderSide(color: Colors.red.shade700, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon-Badge
              Container(
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
              ),
              const SizedBox(width: 12),
              // Textinhalt
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isLatest) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NEU',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            alarm.shortTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (alarm.klartext.isNotEmpty &&
                        alarm.klartext != alarm.shortTitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        alarm.klartext,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (alarm.address.isNotEmpty)
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (alarm.enr.isNotEmpty) ...[
                          Icon(Icons.tag, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Text(
                            alarm.enr,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Icon(Icons.schedule, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 2),
                        Text(
                          _formatTs(alarm.ts),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTs(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} Uhr';
      }
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}. '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts;
    }
  }
}
