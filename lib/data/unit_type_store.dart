import 'package:shared_preferences/shared_preferences.dart';

enum UnitType { erfahren, rettungshunde, helfer }

extension UnitTypeLabel on UnitType {
  String get label {
    switch (this) {
      case UnitType.erfahren:
        return 'Erfahrener Nutzer';
      case UnitType.rettungshunde:
        return 'Rettungshunde';
      case UnitType.helfer:
        return 'Helfer';
    }
  }

  String get description {
    switch (this) {
      case UnitType.erfahren:
        return 'Vollständiges Status-Tableau mit allen Status-Tasten.';
      case UnitType.rettungshunde:
        return 'Vereinfachte Ansicht:\nAm Fahrzeug • Auf Suche • Patient gefunden\n+ Standort • Sprechwunsch';
      case UnitType.helfer:
        return 'Geführte Ansicht für unerfahrene Helfer:\nWache • Im Einsatz • Aufgabe erledigt\n+ Standort • Hilfe anfordern';
    }
  }

  IconData get icon {
    switch (this) {
      case UnitType.erfahren:
        return Icons.dashboard_customize;
      case UnitType.rettungshunde:
        return Icons.pets;
      case UnitType.helfer:
        return Icons.person;
    }
  }
}

class UnitTypeStore {
  static const _key = 'unit_type';

  static Future<UnitType?> load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    if (v == null) return null;
    try {
      return UnitType.values.firstWhere((e) => e.name == v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(UnitType type) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, type.name);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
