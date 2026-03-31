// lib/staerke_editor_screen.dart
import 'package:flutter/material.dart';
import 'data/edp_api.dart';

/// Hilfsklasse zum Kodieren/Dekodieren von ISSIs im BOS-Format.
///
/// Format: 5-stellige ISSI  [Bereich][Wache][FzgTyp 2-stellig][FzgNr]
/// Beispiel: 11831  →  RK RV 01/83-1
///   Stelle 0  : Bereich  (1=RV, 2=FN, 3=SIG, 4=BC)
///   Stelle 1  : Wache    (1–9)
///   Stellen 2–3: Fahrzeugtyp (2 Ziffern, z.B. 83)
///   Stelle 4  : Fahrzeugnummer
class IssiHelper {
  static const Map<String, String> _bereichNames = {
    '1': 'RV',
    '2': 'FN',
    '3': 'SIG',
    '4': 'BC',
  };

  static const Map<String, String> _bereichCodes = {
    'RV': '01',
    'FN': '02',
    'SIG': '03',
    'BC': '04',
  };

  /// Dekodiert eine 5-stellige ISSI in ein lesbares Fahrzeugkennzeichen.
  /// Gibt die ISSI unverändert zurück, wenn das Format nicht passt.
  static String decode(String issi) {
    return issi;
    if (issi.length != 5 || !RegExp(r'^\d{5}$').hasMatch(issi)) return issi;
    final b = _bereichNames[issi[0]] ?? issi[0];
    final w = issi[1].padLeft(2, '0');
    final t = issi.substring(2, 4);
    final n = issi[4];
    return 'RK $b $w/$t-$n';
  }

  /// Kodiert ein Kennzeichen wie "RK RV 01/83-1" in die ISSI "11831".
  /// Gibt null zurück, wenn das Format nicht erkannt wird.
  static String? encode(String display) {
    return display;
    final re = RegExp(r'^RK\s+(\w+)\s+0?(\d)/(\d{2})-(\d)$');
    final m = re.firstMatch(display.trim());
    if (m == null) return null;
    final b = _bereichCodes[m.group(1)];
    if (b == null) return null;
    return '$b${m.group(2)}${m.group(3)}${m.group(4)}';
  }

  static bool isValidIssi(String issi) =>
      issi.length == 5 && RegExp(r'^\d{5}$').hasMatch(issi);
}

/// Melde-Editor: Stärke für ein anderes Fahrzeug (fremde ISSI) melden.
///
/// Die Nachricht wird als SDS mit der ISSI des Zielfahrzeugs gesendet.
/// Damit ist sie auch dann einem Fahrzeug zuzuordnen, wenn die automatische
/// Zuordnung im ELP-System nicht funktioniert (Fahrzeugname steht im Text).
class StaerkeEditorScreen extends StatefulWidget {
  const StaerkeEditorScreen({super.key});

  @override
  State<StaerkeEditorScreen> createState() => _StaerkeEditorScreenState();
}

class _StaerkeEditorScreenState extends State<StaerkeEditorScreen> {
  final _issiCtrl = TextEditingController();

  String _decodedName = '';

  // Stärke-Felder: Führung / Unterführer / Mannschaft
  int _fuehrung = 0;
  int _unterfuehrer = 0;
  int _mannschaft = 0;

  bool _isSending = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void dispose() {
    _issiCtrl.dispose();
    super.dispose();
  }

  void _onIssiChanged(String value) {
    setState(() {
      _decodedName = IssiHelper.isValidIssi(value) ? IssiHelper.decode(value) : '';
    });
  }

  String _buildMessageText() {
    final vehicle = _decodedName.isNotEmpty ? _decodedName : _issiCtrl.text.trim();
    final staerke = 'Stärke: $_fuehrung/$_unterfuehrer/$_mannschaft';
    if (vehicle.isEmpty) return staerke;
    return '$vehicle $staerke';
  }

  Future<void> _send() async {
    final issi = _issiCtrl.text.trim();
    if (issi.isEmpty) {
      _showSnackbar('Bitte ISSI eingeben', success: false);
      return;
    }

    setState(() => _isSending = true);
    try {
      final text = _buildMessageText();
      final res = await EdpApi.instance.sendSdsForIssi(issi, text);
      if (!mounted) return;
      if (res.ok) {
        final label = _decodedName.isNotEmpty ? _decodedName : issi;
        _showSnackbar('Stärke für $label gesendet', success: true);
        _issiCtrl.clear();
        setState(() {
          _decodedName = '';
          _fuehrung = 0;
          _unterfuehrer = 0;
          _mannschaft = 0;
        });
      } else {
        _showSnackbar('Fehler: ${res.statusCode}', success: false);
      }
    } catch (e) {
      if (mounted) _showSnackbar('Fehler: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnackbar(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = _isDark ? Theme.of(context).colorScheme.surface : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Melde-Editor'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: _isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fahrzeug / ISSI ──────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Fahrzeug (ISSI)'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _issiCtrl,
                      onChanged: _onIssiChanged,
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      decoration: InputDecoration(
                        hintText: 'z.B. 11831',
                        counterText: '',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.directions_car_outlined),
                      ),
                    ),
                    if (_decodedName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Text(
                              _decodedName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Format: [Bereich][Wache][FzgTyp 2-stlg][Nr]  •  '
                      '1=RV  2=FN  3=SIG  4=BC',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Stärke ───────────────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Stärke'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStaerkeField(
                            abbr: 'F',
                            label: 'Führung',
                            value: _fuehrung,
                            onChanged: (v) => setState(() => _fuehrung = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStaerkeField(
                            abbr: 'U',
                            label: 'Unterführer',
                            value: _unterfuehrer,
                            onChanged: (v) =>
                                setState(() => _unterfuehrer = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStaerkeField(
                            abbr: 'M',
                            label: 'Mannschaft',
                            value: _mannschaft,
                            onChanged: (v) => setState(() => _mannschaft = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Vorschau ─────────────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Vorschau'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        _buildMessageText(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Senden ───────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _send,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSending ? 'Sendet...' : 'Stärke melden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Color cardBg, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.red.shade800,
      ),
    );
  }

  Widget _buildStaerkeField({
    required String abbr,
    required String label,
    required int value,
    required void Function(int) onChanged,
  }) {
    return Column(
      children: [
        Text(
          abbr,
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _counterButton(
              icon: Icons.remove,
              onTap: value > 0 ? () => onChanged(value - 1) : null,
              active: value > 0,
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _counterButton(
              icon: Icons.add,
              onTap: () => onChanged(value + 1),
              active: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _counterButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool active,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? Colors.red.shade800 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white : Colors.grey.shade400,
        ),
      ),
    );
  }
}
