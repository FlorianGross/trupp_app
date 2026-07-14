// lib/dienstanmeldung_screen.dart
//
// Dienstanmeldung für Sanitätsdienste: erfasst Einheit, Namen und
// Qualifikationen der Teammitglieder sowie die Personenstärke und sendet
// die Anmeldung als SDS an das ELW / die Leitstelle.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_prefs.dart';
import 'data/edp_api.dart';
import 'theme/brand_colors.dart';

/// Bekannte Sanitäts-Qualifikationen (Kürzel → Klartext für die Auswahl).
const Map<String, String> _kQualifications = {
  'SH': 'Sanitätshelfer',
  'San': 'Sanitäter',
  'RH': 'Rettungshelfer',
  'RS': 'Rettungssanitäter',
  'RettAss': 'Rettungsassistent',
  'NFS': 'Notfallsanitäter',
  'NA': 'Notarzt',
  'ZF': 'Zugführer',
  'GF': 'Gruppenführer',
  'Sonstige': 'Sonstige',
};

class _Member {
  final TextEditingController name = TextEditingController();
  String qual = 'San';
}

class DienstanmeldungScreen extends StatefulWidget {
  const DienstanmeldungScreen({super.key});

  @override
  State<DienstanmeldungScreen> createState() => _DienstanmeldungScreenState();
}

class _DienstanmeldungScreenState extends State<DienstanmeldungScreen> {
  final _einheitCtrl = TextEditingController();
  final List<_Member> _members = [_Member()];

  // Personenstärke: Führung / Unterführer / Mannschaft
  int _fuehrung = 0;
  int _unterfuehrer = 0;
  int _mannschaft = 0;

  bool _isSending = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _loadEinheit();
  }

  Future<void> _loadEinheit() async {
    final prefs = await SharedPreferences.getInstance();
    final trupp = (prefs.getString(AppPrefsKeys.trupp) ?? '').trim();
    if (trupp.isNotEmpty && mounted) {
      setState(() => _einheitCtrl.text = trupp);
    }
  }

  @override
  void dispose() {
    _einheitCtrl.dispose();
    for (final m in _members) {
      m.name.dispose();
    }
    super.dispose();
  }

  int get _gesamt => _fuehrung + _unterfuehrer + _mannschaft;

  void _addMember() {
    setState(() => _members.add(_Member()));
  }

  void _removeMember(int index) {
    if (_members.length <= 1) return;
    setState(() {
      _members.removeAt(index).name.dispose();
    });
  }

  String _buildMessageText() {
    final einheit = _einheitCtrl.text.trim();
    final header =
        'Dienstanmeldung${einheit.isNotEmpty ? ' $einheit' : ''}';
    final staerke = 'Stärke: $_fuehrung/$_unterfuehrer/$_mannschaft//$_gesamt';
    final roster = _members
        .where((m) => m.name.text.trim().isNotEmpty)
        .map((m) => '- ${m.name.text.trim()} (${m.qual})')
        .join('\n');
    return '$header\n$staerke'
        '${roster.isNotEmpty ? '\nKräfte:\n$roster' : ''}';
  }

  Future<void> _send() async {
    final hasRoster =
        _members.any((m) => m.name.text.trim().isNotEmpty);
    if (!hasRoster && _gesamt == 0) {
      _showSnackbar('Bitte mindestens ein Mitglied oder eine Stärke angeben',
          success: false);
      return;
    }

    setState(() => _isSending = true);
    try {
      final res = await EdpApi.instance.sendSdsText(_buildMessageText());
      if (!mounted) return;
      if (res.ok) {
        _showSnackbar('Dienstanmeldung an ELW gesendet', success: true);
        Navigator.of(context).pop();
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
    final brand = Theme.of(context).brand;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? brand.success : brand.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color get _fieldFill =>
      _isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade50;
  Color get _fieldBorder =>
      _isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200;

  @override
  Widget build(BuildContext context) {
    final cardBg =
        _isDark ? Theme.of(context).colorScheme.surface : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dienstanmeldung'),
        elevation: 0,
        centerTitle: true,
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
              // ── Einheit ──────────────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Einheit'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _einheitCtrl,
                      decoration: _inputDecoration(
                        hint: 'z. B. SEG Musterstadt',
                        icon: Icons.groups,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Teammitglieder ───────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _sectionTitle('Teammitglieder'),
                        const Spacer(),
                        Text(
                          '${_members.where((m) => m.name.text.trim().isNotEmpty).length}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _members.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildMemberRow(i),
                      ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Mitglied hinzufügen'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Personenstärke ───────────────────────────────────────────
              _buildCard(
                cardBg: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _sectionTitle('Personenstärke'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Gesamt: $_gesamt',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                    _sectionTitle('Vorschau (SDS an ELW)'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _fieldFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _fieldBorder),
                      ),
                      child: Text(
                        _buildMessageText(),
                        style: const TextStyle(
                          fontSize: 13,
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
                  label: Text(_isSending
                      ? 'Sendet...'
                      : 'Dienstanmeldung an ELW senden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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

  Widget _buildMemberRow(int index) {
    final m = _members[index];
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: m.name,
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration(
              hint: 'Name',
              icon: Icons.person_outline,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: m.qual,
            isExpanded: true,
            decoration: _inputDecoration(),
            items: _kQualifications.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.key, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => m.qual = v);
            },
          ),
        ),
        IconButton(
          onPressed: _members.length > 1 ? () => _removeMember(index) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: Colors.grey,
          tooltip: 'Entfernen',
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: _fieldFill,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
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
        color: Theme.of(context).colorScheme.primary,
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
              fontSize: 12,
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? cs.primary : _fieldBorder,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? cs.onPrimary : Colors.grey.shade500,
        ),
      ),
    );
  }
}
