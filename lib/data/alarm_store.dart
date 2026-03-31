// lib/data/alarm_store.dart
//
// Persistiert empfangene Alarme als JSON-Liste in SharedPreferences.
// Maximal 50 Einträge, neueste zuerst.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_model.dart';

class AlarmStore {
  static const _kKey = 'alarm_history';
  static const _kMaxEntries = 50;

  /// Fügt einen Alarm an den Anfang der Liste ein.
  static Future<void> add(AlarmData alarm) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getAll(prefs: prefs);

    // Duplikat-Schutz
    if (existing.isNotEmpty &&
        existing.first.deduplicationKey == alarm.deduplicationKey) {
      return;
    }

    final updated = [alarm, ...existing];
    if (updated.length > _kMaxEntries) {
      updated.removeRange(_kMaxEntries, updated.length);
    }

    await prefs.setString(
      _kKey,
      jsonEncode(updated.map((a) => a.toJson()).toList()),
    );
  }

  /// Gibt alle gespeicherten Alarme zurück (neueste zuerst).
  static Future<List<AlarmData>> getAll({SharedPreferences? prefs}) async {
    prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AlarmData.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Löscht alle gespeicherten Alarme.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
