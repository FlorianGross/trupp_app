// lib/alarm_detail_screen.dart
//
// Vollbild-Ansicht für einen eingehenden EDP-Alarm.
// Zeigt alle relevanten Einsatzinformationen und bietet einen
// "Navigieren"-Button der die Einsatzadresse in der Karten-App öffnet.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/alarm_model.dart';
import 'alarm_notification.dart';

class AlarmDetailScreen extends StatelessWidget {
  final AlarmData alarm;

  const AlarmDetailScreen({super.key, required this.alarm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: const Text('Alarmierung'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            AlarmNotificationService.clearPendingAlarm();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildContent(context)),
            _buildNavigateButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stichwort / Klartext – Hauptüberschrift
          _AlarmHeader(alarm: alarm),
          const SizedBox(height: 16),

          // Adresse prominent
          if (alarm.address.isNotEmpty)
            _InfoCard(
              icon: Icons.location_on,
              label: 'Adresse',
              value: alarm.address,
              highlight: true,
            ),

          const SizedBox(height: 8),

          // Kerninformationen
          if (alarm.enr.isNotEmpty)
            _InfoCard(icon: Icons.tag, label: 'Einsatznummer', value: alarm.enr),
          if (alarm.signal.isNotEmpty)
            _InfoCard(icon: Icons.warning_amber, label: 'Sondersignal', value: alarm.signal),
          if (alarm.meldung.isNotEmpty)
            _InfoCard(icon: Icons.message, label: 'Meldung', value: alarm.meldung),
          if (alarm.objekt.isNotEmpty)
            _InfoCard(icon: Icons.business, label: 'Objekt', value: alarm.objekt),
          if (alarm.mittel.isNotEmpty)
            _InfoCard(icon: Icons.local_fire_department, label: 'Einsatzmittel', value: alarm.mittel),
          if (alarm.ts.isNotEmpty)
            _InfoCard(icon: Icons.schedule, label: 'Alarmzeit', value: _formatTs(alarm.ts)),
        ],
      ),
    );
  }

  Widget _buildNavigateButton(BuildContext context) {
    if (alarm.address.isEmpty && alarm.ort.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.red.shade900,
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.navigation, size: 26),
          label: const Text('Navigieren'),
          onPressed: () => _openNavigation(context),
        ),
      ),
    );
  }

  Future<void> _openNavigation(BuildContext context) async {
    final uri = Uri.parse(alarm.mapsUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Karten-App gefunden.')),
        );
      }
    }
  }

  String _formatTs(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} Uhr';
    } catch (_) {
      return ts;
    }
  }
}

// ---------------------------------------------------------------------------
// Hilfs-Widgets
// ---------------------------------------------------------------------------

class _AlarmHeader extends StatelessWidget {
  final AlarmData alarm;

  const _AlarmHeader({required this.alarm});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.campaign, color: Colors.white, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                alarm.stichwort.isNotEmpty ? alarm.stichwort : 'Alarm',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (alarm.klartext.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            alarm.klartext,
            style: TextStyle(color: Colors.red.shade100, fontSize: 16),
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? Colors.white : Colors.red.shade800,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: highlight ? Colors.red.shade900 : Colors.red.shade200),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: highlight ? Colors.red.shade700 : Colors.red.shade200,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: highlight ? Colors.red.shade900 : Colors.white,
                      fontWeight:
                          highlight ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
