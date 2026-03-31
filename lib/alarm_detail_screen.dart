// lib/alarm_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/alarm_model.dart';
import 'data/edp_api.dart';
import 'alarm_notification.dart';
import 'keypad_widget.dart';

class AlarmDetailScreen extends StatefulWidget {
  final AlarmData alarm;

  const AlarmDetailScreen({super.key, required this.alarm});

  @override
  State<AlarmDetailScreen> createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends State<AlarmDetailScreen> {
  AlarmData get alarm => widget.alarm;
  int? _lastSentStatus;
  bool _sendingStatus = false;
  bool _rejected = false;

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
            _buildStatusButtons(context),
            _buildBottomRow(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inhaltsbereich
  // ---------------------------------------------------------------------------

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AlarmHeader(alarm: alarm),
          const SizedBox(height: 16),
          if (alarm.address.isNotEmpty)
            _InfoCard(icon: Icons.location_on, label: 'Adresse', value: alarm.address, highlight: true),
          const SizedBox(height: 8),
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

  // ---------------------------------------------------------------------------
  // FMS-Status-Schnellwahl (Keypad-Stil)
  // ---------------------------------------------------------------------------

  static const _quickStatuses = [3, 4, 7, 8];

  Widget _buildStatusButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: _quickStatuses.map((code) {
          final cfg = statusConfigs[code]!;
          final isActive = _lastSentStatus == code;
          final isLoading = _sendingStatus && isActive;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _KeypadStyleButton(
                config: cfg,
                isSelected: isActive,
                isLoading: isLoading,
                onTap: _sendingStatus || _rejected ? null : () => _sendStatus(code),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _sendStatus(int code) async {
    setState(() { _sendingStatus = true; _lastSentStatus = code; });
    try {
      final result = await EdpApi.instance.sendStatus(code);
      if (!mounted) return;
      final cfg = statusConfigs[code]!;
      final msg = result.ok
          ? 'Status ${code} – ${cfg.title} gesendet'
          : 'Fehler (HTTP ${result.statusCode})';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kein EDP-Server konfiguriert.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingStatus = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Untere Aktionsleiste: Navigieren + Ablehnen
  // ---------------------------------------------------------------------------

  Widget _buildBottomRow(BuildContext context) {
    if (alarm.address.isEmpty && alarm.ort.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: _buildRejectButton(context, fullWidth: true),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Row(
        children: [
          Expanded(child: _buildRejectButton(context)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: _buildNavigateButton(context)),
        ],
      ),
    );
  }

  Widget _buildNavigateButton(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.red.shade900,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.navigation, size: 22),
        label: const Text('Navigieren'),
        onPressed: () => _openNavigation(context),
      ),
    );
  }

  Widget _buildRejectButton(BuildContext context, {bool fullWidth = false}) {
    return SizedBox(
      height: 54,
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _rejected ? Colors.grey.shade700 : Colors.red.shade700,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Colors.white38),
        ),
        icon: Icon(_rejected ? Icons.check : Icons.cancel_outlined, size: 20),
        label: Text(_rejected ? 'Abgelehnt' : 'Ablehnen'),
        onPressed: _rejected ? null : () => _showRejectSheet(context),
      ),
    );
  }

  void _showRejectSheet(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Einsatz ablehnen',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'ENR ${alarm.enr} – ${alarm.shortTitle}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ablehnungsgrund (optional)',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  filled: true,
                  fillColor: Colors.grey.shade800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 2,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Ablehnung per SDS senden'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendRejection(reasonCtrl.text.trim());
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendRejection(String reason) async {
    final text = [
      'ABLEHNUNG',
      'ENR: ${alarm.enr}',
      alarm.shortTitle,
      if (reason.isNotEmpty) 'Grund: $reason',
    ].join(' | ');

    try {
      final api = EdpApi.instance;
      final result = alarm.issi.isNotEmpty
          ? await api.sendSdsForIssi(alarm.issi, text)
          : await api.sendSdsText(text);
      if (!mounted) return;
      if (result.ok) {
        setState(() => _rejected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ablehnung per SDS gesendet.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SDS-Fehler (HTTP ${result.statusCode})')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kein EDP-Server konfiguriert.')),
        );
      }
    }
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
// Status-Button im Keypad-Stil (wiederverwendet statusConfigs + Gradient)
// ---------------------------------------------------------------------------

class _KeypadStyleButton extends StatelessWidget {
  final StatusConfig config;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;

  const _KeypadStyleButton({
    required this.config,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !isSelected;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: disabled ? 0.4 : 1.0,
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isSelected
                    ? [Colors.red.shade600, Colors.red.shade800]
                    : [Colors.red.shade700, Colors.red.shade900],
              ),
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.shade700.withOpacity(0.3),
                  blurRadius: isSelected ? 8 : 4,
                  offset: Offset(0, isSelected ? 4 : 2),
                ),
              ],
            ),
            child: isLoading
                ? const Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(config.icon, size: 20, color: Colors.white),
                            const SizedBox(width: 3),
                            Text('${config.number}',
                                style: const TextStyle(fontSize: 20,
                                    fontWeight: FontWeight.bold, color: Colors.white, height: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(config.title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w600, color: Colors.white, height: 1.1)),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hilfs-Widgets (unverändert)
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
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (alarm.klartext.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(alarm.klartext, style: TextStyle(color: Colors.red.shade100, fontSize: 16)),
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

  const _InfoCard({required this.icon, required this.label, required this.value, this.highlight = false});

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
            Icon(icon, size: 20,
                color: highlight ? Colors.red.shade900 : Colors.red.shade200),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11,
                          color: highlight ? Colors.red.shade700 : Colors.red.shade200,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(fontSize: 15,
                          color: highlight ? Colors.red.shade900 : Colors.white,
                          fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
