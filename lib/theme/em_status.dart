// lib/theme/em_status.dart
//
// Zentrale FMS-Statusfarben für Einsatzmittel (Fahrzeuge) — ersetzt die
// bisher duplizierten _statusColor/_markerColor-Helfer in
// einsatz_detail_screen und fahrzeug_karte_screen.
import 'package:flutter/material.dart';

/// Gruppierte FMS-Statusfarbe: 1/2 verfügbar, 3/4 im Einsatz,
/// 5 Sprechwunsch, 6 nicht einsatzbereit.
Color emStatusColor(String? status) {
  switch (status) {
    case '1':
    case '2':
      return Colors.green.shade600;
    case '3':
    case '4':
      return Colors.orange.shade600;
    case '5':
      return Colors.blue.shade600;
    case '6':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade600;
  }
}
