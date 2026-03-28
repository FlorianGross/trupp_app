// lib/staerke_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/edp_api.dart';

/// Hilfsklasse zum Kodieren/Dekodieren von ISSIs im BOS-Format.
///
/// ISSI = [Bereich][Wache][FzgTyp][FzgNr]   (variable Länge)
/// Anzeige: "RK [BereichName] [Wache 2-stlg]/[FzgTyp 2-stlg]-[FzgNr]"
/// Beispiel: Bereich=1(RV), Wache=1, Typ=83, Nr=1  →  ISSI 11831  / "RK RV 01/83-1"
class IssiHelper {
  /// Öffentlich – wird für das Dropdown benötigt.
  static const Map<String, String> bereichNames = {
    '1': 'RV',
    '2': 'FN',
    '3': 'SIG',
    '4': 'BC',
  };

  static const Map<String, String> _bereichCodes = {
    'RV': '1',
    'FN': '2',
    'SIG': '3',
    'BC': '4',
  };

  /// Erstellt die Anzeige-Bezeichnung aus den Einzelkomponenten.
  /// Wache und Fahrzeugtyp werden auf 2 Stellen aufgefüllt (01, 02 …).
  static String buildDisplayName({
    required String bereichCode,
    required int wache,
    required int fahrzeugTyp,
    required int anzahl,
  }) {
    final b = bereichNames[bereichCode] ?? bereichCode;
    final w = wache.toString().padLeft(2, '0');
    final t = fahrzeugTyp.toString().padLeft(2, '0');
    return 'RK $b $w/$t-$anzahl';
  }

  /// Erstellt die ISSI aus den Einzelkomponenten.
  static String buildIssi({
    required String bereichCode,
    required int wache,
    required int fahrzeugTyp,
    required int anzahl,
  }) {
    return '$bereichCode$wache$fahrzeugTyp$anzahl';
  }

  /// Dekodiert eine 5-stellige ISSI in ein lesbares Fahrzeugkennzeichen.
  /// Gibt die ISSI unverändert zurück, wenn das Format nicht passt.
  static String decode(String issi) {
    if (issi.length != 5 || !RegExp(r'^\d{5}$').hasMatch(issi)) return issi;
    final b = bereichNames[issi[0]] ?? issi[0];
    final w = issi[1].padLeft(2, '0');
    final t = issi.substring(2, 4);
    final n = issi[4];
    return 'RK $b $w/$t-$n';
  }

  /// Kodiert ein Kennzeichen wie "RK RV 01/83-1" in die ISSI "11831".
  /// Gibt null zurück, wenn das Format nicht erkannt wird.
  static String? encode(String display) {
    final re = RegExp(r'^RK\s+(\w+)\s+0?(\d+)/(\d+)-(\d+)$');
    final m = re.firstMatch(display.trim());
    if (m == null) return null;
    final b = _bereichCodes[m.group(1)];
    if (b == null) return null;
    return '$b${m.group(2)}${m.group(3)}${m.group(4)}';
  }

  static bool isValidIssi(String issi) =>
      issi.length == 5 && RegExp(r'^\d{5}$').hasMatch(issi);
}

// ---------------------------------------------------------------------------
// Melde-Editor
// ---------------------------------------------------------------------------

/// Melde-Editor: Stärke für ein anderes Fahrzeug (fremde ISSI) melden.
///
/// Das Fahrzeug wird über Landkreis-Dropdown + Freitextfelder für Wache,
/// Fahrzeugtyp und Anzahl zusammengesetzt. Die resultierende ISSI und der
/// Fahrzeugname (im Text als Fallback) werden automatisch berechnet.
class StaerkeEditorScreen extends StatefulWidget {
  const StaerkeEditorScreen({super.key});

  @override
  State<StaerkeEditorScreen> createState() => _StaerkeEditorScreenState();
}

class _StaerkeEditorScreenState extends State<StaerkeEditorScreen> {
  // Fahrzeug-Auswahl
  String _bereichCode = '1'; // Default: RV
  final _wacheCtrl = TextEditingController();
  final _fahrzeugTypCtrl = TextEditingController();
  final _anzahlCtrl = TextEditingController();

  // Stärke-Felder: Führung / Unterführer / Mannschaft
  int _fuehrung = 0;
  int _unterfuehrer = 0;
  int _mannschaft = 0;

  bool _isSending = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // ── Berechnete Werte ──────────────────────────────────────────────────────

  /// Gibt null zurück, wenn noch nicht alle Felder ausgefüllt sind.
  ({String issi, String displayName})? get _computed {
    final wache = int.tryParse(_wacheCtrl.text.trim());
    final typ = int.tryParse(_fahrzeugTypCtrl.text.trim());
    final anzahl = int.tryParse(_anzahlCtrl.text.trim());
    if (wache == null || typ == null || anzahl == null) return null;
    if (wache < 1 || wache > 99) return null;
    if (typ < 1) return null;
    if (anzahl < 1) return null;
    return (
      issi: IssiHelper.buildIssi(
        bereichCode: _bereichCode,
        wache: wache,
        fahrzeugTyp: typ,
        anzahl: anzahl,
      ),
      displayName: IssiHelper.buildDisplayName(
        bereichCode: _bereichCode,
        wache: wache,
        fahrzeugTyp: typ,
        anzahl: anzahl,
      ),
    );
  }

  String _buildMessageText() {
    final c = _computed;
    final vehicle = c?.displayName ?? '—';
    return '$vehicle Stärke: $_fuehrung/$_unterfuehrer/$_mannschaft';
  }

  // ── Senden ───────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final c = _computed;
    if (c == null) {
      _showSnackbar('Bitte alle Fahrzeugfelder ausfüllen', success: false);
      return;
    }

    setState(() => _isSending = true);
    try {
      final text = _buildMessageText();
      final res = await EdpApi.instance.sendSdsForIssi(c.issi, text);
      if (!mounted) return;
      if (res.ok) {
        _showSnackbar('Stärke für ${c.displayName} gesendet', success: true);
        _wacheCtrl.clear();
        _fahrzeugTypCtrl.clear();
        _anzahlCtrl.clear();
        setState(() {
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackbar(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _wacheCtrl.dispose();
    _fahrzeugTypCtrl.dispose();
    _anzahlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg =
        _isDark ? Theme.of(context).colorScheme.surface : Colors.white;
    final c = _computed;

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
              // ── Fahrzeug-Auswahl ─────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Fahrzeug'),
                    const SizedBox(height: 12),

                    // Landkreis-Dropdown
                    _fieldLabel('Landkreis'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _bereichCode,
                      decoration: _inputDecoration(
                        icon: Icons.location_city_outlined,
                      ),
                      items: IssiHelper.bereichNames.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text('${e.value}  (${e.key})'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _bereichCode = v);
                      },
                    ),

                    const SizedBox(height: 12),

                    // Wache + Fahrzeugtyp in einer Zeile
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Wache  (1–99)'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _wacheCtrl,
                                onChanged: (_) => setState(() {}),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                decoration: _inputDecoration(
                                  hint: 'z.B. 1',
                                  icon: Icons.home_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Fahrzeugtyp  (RTW=83)'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _fahrzeugTypCtrl,
                                onChanged: (_) => setState(() {}),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                decoration: _inputDecoration(
                                  hint: 'z.B. 83',
                                  icon: Icons.directions_car_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Anzahl (Fahrzeugnummer)
                    _fieldLabel('Anzahl / Fahrzeugnummer'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _anzahlCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      decoration: _inputDecoration(
                        hint: 'z.B. 1',
                        icon: Icons.tag_outlined,
                      ),
                    ),

                    // Berechnete ISSI + Bezeichnung
                    if (c != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
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
                            Expanded(
                              child: Text(
                                '${c.displayName}   ·   ISSI ${c.issi}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            onChanged: (v) =>
                                setState(() => _mannschaft = v),
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

  // ── Helper-Widgets ────────────────────────────────────────────────────────

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

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade800,
        ),
      );

  Widget _fieldLabel(String text) => Text(
        text,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      );

  InputDecoration _inputDecoration({String? hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon: Icon(icon, size: 18),
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
              primary: false,
              enabled: value > 0,
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
              primary: true,
              enabled: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _counterButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool primary,
    required bool enabled,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: (primary && enabled)
              ? Colors.red.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: (primary && enabled)
              ? Colors.white
              : (enabled ? Colors.black87 : Colors.grey.shade400),
        ),
      ),
    );
  }
}
