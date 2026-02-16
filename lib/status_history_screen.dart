// lib/status_history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keypad_widget.dart';

/// Ein einzelner Statusverlauf-Eintrag
class StatusEntry {
  final int status;
  final int timestampMs;

  StatusEntry({required this.status, required this.timestampMs});

  Map<String, dynamic> toJson() => {'s': status, 't': timestampMs};

  factory StatusEntry.fromJson(Map<String, dynamic> json) {
    return StatusEntry(
      status: json['s'] as int,
      timestampMs: json['t'] as int,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestampMs);
}

/// Verwaltet den Statusverlauf in SharedPreferences
class StatusHistory {
  static const _key = 'status_history';
  static const _maxEntries = 200;

  static Future<void> add(int status) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _load(prefs);
    entries.insert(0, StatusEntry(
      status: status,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ));

    // Auf maxEntries begrenzen
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }

    await prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  static Future<List<StatusEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _load(prefs);
  }

  static Future<List<StatusEntry>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => StatusEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

/// Screen zur Anzeige des Statusverlaufs
class StatusHistoryScreen extends StatefulWidget {
  const StatusHistoryScreen({super.key});

  @override
  State<StatusHistoryScreen> createState() => _StatusHistoryScreenState();
}

class _StatusHistoryScreenState extends State<StatusHistoryScreen> {
  List<StatusEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await StatusHistory.getAll();
    if (mounted) setState(() => _entries = entries);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d.$mo.$y';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? Colors.red.shade900 : Colors.red.shade800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statusverlauf'),
        backgroundColor: appBarBg,
        elevation: 0,
        centerTitle: true,
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('Noch keine Statuswechsel'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final config = statusConfigs[entry.status];
                final dt = entry.dateTime;

                // Datumsgruppen-Header
                Widget? header;
                if (index == 0 ||
                    _formatDate(_entries[index - 1].dateTime) != _formatDate(dt)) {
                  header = Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      _formatDate(dt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  );
                }

                final tile = Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Theme.of(context).colorScheme.surface
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // Status-Nummer als Badge
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: (config?.color ?? Colors.grey).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${entry.status}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: config?.color ?? Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Titel
                      Expanded(
                        child: Text(
                          config?.title ?? 'Status ${entry.status}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Uhrzeit
                      Text(
                        _formatTime(dt),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );

                if (header != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, tile],
                  );
                }
                return tile;
              },
            ),
    );
  }
}
