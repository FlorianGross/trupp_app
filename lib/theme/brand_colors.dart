// lib/theme/brand_colors.dart
//
// Semantische Farben, die NICHT direkt aus ColorScheme stammen, aber app-weit
// konsistent verwendet werden sollen (Deployment-States, Verbindungs-Status,
// Pending-Queue-Warnung, etc.).
//
// Statt verstreuter `Colors.green.shade700`/`Colors.orange.shade100`-Aufrufe
// werden diese Tokens an EINER Stelle definiert und im Dark Mode angepasst.
//
// Verwendung:
//   final brand = Theme.of(context).extension<BrandColors>()!;
//   Container(color: brand.deployed)

import 'package:flutter/material.dart';

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  /// Hintergrund-Farbe für den „EINSATZ"-State-Bar
  final Color deployed;

  /// Hintergrund-Farbe für den „BEREIT"-State-Bar
  final Color ready;

  /// Verbindung OK
  final Color connectionOk;

  /// Verbindung mit Pending-Queue
  final Color connectionDegraded;

  /// Keine Verbindung
  final Color connectionOffline;

  /// Pending-Queue (warnender Akzent, z.B. Chip-Hintergrund)
  final Color queuePending;

  /// Erfolg-Snackbar
  final Color success;

  /// Warnung-Snackbar / nicht-fataler Hinweis
  final Color warning;

  const BrandColors({
    required this.deployed,
    required this.ready,
    required this.connectionOk,
    required this.connectionDegraded,
    required this.connectionOffline,
    required this.queuePending,
    required this.success,
    required this.warning,
  });

  /// Light-Mode-Tokens
  static const BrandColors light = BrandColors(
    deployed: Color(0xFF388E3C),          // green 700
    ready: Color(0xFF1976D2),             // blue 700
    connectionOk: Color(0xFF69F0AE),      // greenAccent
    connectionDegraded: Color(0xFFFFAB40), // orangeAccent
    connectionOffline: Color(0xFFFF5252), // redAccent
    queuePending: Color(0xFFFFE0B2),      // orange 100
    success: Color(0xFF43A047),           // green 600
    warning: Color(0xFFF57C00),           // orange 700
  );

  /// Dark-Mode-Tokens (sattere/dunklere Varianten)
  static const BrandColors dark = BrandColors(
    deployed: Color(0xFF2E7D32),          // green 800
    ready: Color(0xFF1565C0),             // blue 800
    connectionOk: Color(0xFF69F0AE),
    connectionDegraded: Color(0xFFFFAB40),
    connectionOffline: Color(0xFFFF5252),
    queuePending: Color(0xFF5D4037),      // brown 700 - weniger blendend
    success: Color(0xFF43A047),
    warning: Color(0xFFF57C00),
  );

  @override
  BrandColors copyWith({
    Color? deployed,
    Color? ready,
    Color? connectionOk,
    Color? connectionDegraded,
    Color? connectionOffline,
    Color? queuePending,
    Color? success,
    Color? warning,
  }) {
    return BrandColors(
      deployed: deployed ?? this.deployed,
      ready: ready ?? this.ready,
      connectionOk: connectionOk ?? this.connectionOk,
      connectionDegraded: connectionDegraded ?? this.connectionDegraded,
      connectionOffline: connectionOffline ?? this.connectionOffline,
      queuePending: queuePending ?? this.queuePending,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      deployed: Color.lerp(deployed, other.deployed, t)!,
      ready: Color.lerp(ready, other.ready, t)!,
      connectionOk: Color.lerp(connectionOk, other.connectionOk, t)!,
      connectionDegraded:
          Color.lerp(connectionDegraded, other.connectionDegraded, t)!,
      connectionOffline:
          Color.lerp(connectionOffline, other.connectionOffline, t)!,
      queuePending: Color.lerp(queuePending, other.queuePending, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// Bequeme Zugriffs-Extension: `Theme.of(context).brand.deployed`
extension BrandColorsOnThemeData on ThemeData {
  BrandColors get brand =>
      extension<BrandColors>() ?? BrandColors.light;
}
