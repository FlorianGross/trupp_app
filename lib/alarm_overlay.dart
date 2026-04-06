// lib/alarm_overlay.dart
//
// Flutter-Overlay das über anderen Apps angezeigt wird (SYSTEM_ALERT_WINDOW).
// Zeigt Alarmdetails + Status-Schnellbuttons (3/4/7/8) + Schließen-Button.
//
// Einstiegspunkt: overlayMain() – wird von flutter_overlay_window als
// separater Flutter-Engine-Isolate gestartet.

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/alarm_model.dart';
import 'data/edp_api.dart';

const kOverlayOpenDetail = 'overlay_open_detail';

/// Entry-Point für das Overlay – muss vm:entry-point sein und in main.dart
/// referenziert werden, damit der Flutter-Linker ihn nicht entfernt.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AlarmOverlayApp());
}

class _AlarmOverlayApp extends StatelessWidget {
  const _AlarmOverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AlarmOverlayWidget(),
    );
  }
}

class AlarmOverlayWidget extends StatefulWidget {
  const AlarmOverlayWidget({super.key});

  @override
  State<AlarmOverlayWidget> createState() => _AlarmOverlayWidgetState();
}

class _AlarmOverlayWidgetState extends State<AlarmOverlayWidget> {
  AlarmData? _alarm;
  int? _sentStatus;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Alarm-Daten empfangen (wird nach showOverlay via shareData gesendet)
    FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data is String) {
        final alarm = AlarmData.tryParseJsonString(data);
        if (alarm != null && mounted) {
          await EdpApi.ensureInitialized();
          setState(() => _alarm = alarm);
        }
      }
    });
  }

  Future<void> _sendStatus(int code) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _sentStatus = code;
    });
    try {
      await EdpApi.instance.sendStatus(code);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = _alarm;
    if (alarm == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.shade700, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(alarm),
              _buildInfo(alarm),
              const Divider(color: Color(0xFF2C2C2E), height: 1),
              _buildStatusButtons(),
              _buildCloseButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AlarmData alarm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade800,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alarm.shortTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(AlarmData alarm) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alarm.klartext.isNotEmpty && alarm.klartext != alarm.shortTitle) ...[
            Text(
              alarm.klartext,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
          ],
          if (alarm.address.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    alarm.address,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          if (alarm.enr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'ENR ${alarm.enr}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusButtons() {
    const configs = {
      3: ('Auftrag', Icons.assignment_turned_in),
      4: ('Ziel', Icons.flag),
      7: ('Transport', Icons.local_hospital),
      8: ('Angek.', Icons.check_circle),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: configs.entries.map((e) {
          final code = e.key;
          final label = e.value.$1;
          final icon = e.value.$2;
          final isSelected = _sentStatus == code;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: _sending ? null : () => _sendStatus(code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.red.shade700, Colors.red.shade900],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : Border.all(color: Colors.transparent, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(height: 3),
                      Text(
                        '$code',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(color: Colors.white70, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => FlutterOverlayWindow.closeOverlay(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text('Schließen'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextButton(
              onPressed: _openDetail,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2C2C2E),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Details'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail() async {
    // Flag setzen, damit die App nach dem Overlay-Schließen zur Detail-Ansicht navigiert
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOverlayOpenDetail, true);
    await FlutterOverlayWindow.closeOverlay();
  }
}
