// lib/pro/staerke_edp_screen.dart
import 'package:flutter/material.dart';
import '../data/edp_api.dart';
import '../data/edp_api_pro.dart';

class StaerkeEdpScreen extends StatefulWidget {
  const StaerkeEdpScreen({super.key});

  @override
  State<StaerkeEdpScreen> createState() => _StaerkeEdpScreenState();
}

class _StaerkeEdpScreenState extends State<StaerkeEdpScreen> {
  List<EdpEinsatzmittel> _allMittel = [];
  List<EdpEinsatzmittel> _filtered = [];
  EdpEinsatzmittel? _selected;
  String _searchText = '';

  int _fuehrung = 0;
  int _unterfuehrer = 0;
  int _mannschaft = 0;

  bool _loading = true;
  bool _sending = false;
  String? _loadError;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = EdpApiPro.instance;
    if (api == null) {
      setState(() {
        _loading = false;
        _loadError = 'Pro-API nicht initialisiert. Bitte zuerst anmelden.';
      });
      return;
    }
    final result = await api.getEinsatzmittel();
    if (!mounted) return;
    if (result.ok) {
      final items = (result.data ?? [])
        ..sort((a, b) => a.rufname.compareTo(b.rufname));
      setState(() {
        _allMittel = items;
        _filtered = items;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _loadError = result.error ?? 'Fehler ${result.statusCode}';
      });
    }
  }

  void _onSearch(String q) {
    setState(() {
      _searchText = q;
      if (q.isEmpty) {
        _filtered = _allMittel;
      } else {
        final lower = q.toLowerCase();
        _filtered = _allMittel
            .where((m) =>
                m.rufname.toLowerCase().contains(lower) ||
                (m.rufnameLang?.toLowerCase().contains(lower) ?? false) ||
                (m.typ?.toLowerCase().contains(lower) ?? false))
            .toList();
      }
    });
  }

  void _select(EdpEinsatzmittel m) {
    setState(() {
      _selected = m;
      _fuehrung = m.besatzung0 ?? 0;
      _unterfuehrer = m.besatzung1 ?? 0;
      _mannschaft = m.besatzung2 ?? 0;
    });
  }

  Future<void> _send() async {
    final sel = _selected;
    if (sel == null) return;
    setState(() => _sending = true);
    final res = await EdpApiPro.instance!.updateBesatzung(
      sel.rufname,
      fuehrung: _fuehrung,
      unterfuehrer: _unterfuehrer,
      mannschaft: _mannschaft,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Stärke für ${sel.displayName} gemeldet'),
        backgroundColor: Colors.green,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler: ${res.error ?? res.statusCode}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stärke melden (Pro)'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Aktualisieren'),
        ],
      ),
      backgroundColor: _isDark ? null : Colors.grey[100],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _load, child: const Text('Erneut versuchen')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final cardBg =
        _isDark ? Theme.of(context).colorScheme.surface : Colors.white;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCard(
              cardBg: cardBg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Einsatzmittel auswählen'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Suchen (Rufname, Typ…)',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _searchText.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearch('');
                              })
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _selected != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: Colors.green.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selected!.displayName,
                                  style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (_selected!.status != null)
                                Text(
                                  'S${_selected!.status}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade600),
                                ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: Colors.grey),
                              SizedBox(width: 8),
                              Text('Noch kein Fahrzeug gewählt',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text('Keine Treffer',
                                style: TextStyle(
                                    color: Colors.grey.shade500)))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final m = _filtered[i];
                              final isSel =
                                  _selected?.rufname == m.rufname;
                              return ListTile(
                                dense: true,
                                selected: isSel,
                                selectedTileColor: Colors.red.shade50,
                                leading: Icon(
                                  Icons.directions_car,
                                  color: isSel
                                      ? Colors.red.shade800
                                      : Colors.grey,
                                  size: 20,
                                ),
                                title: Text(m.displayName,
                                    style:
                                        const TextStyle(fontSize: 13)),
                                subtitle: m.typ != null
                                    ? Text(m.typ!,
                                        style: const TextStyle(
                                            fontSize: 11))
                                    : null,
                                trailing: m.status != null
                                    ? Text('S${m.status}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Colors.grey.shade600))
                                    : null,
                                onTap: () => _select(m),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                          child: _staerkeField(
                              abbr: 'F',
                              label: 'Führung',
                              value: _fuehrung,
                              onChanged: (v) =>
                                  setState(() => _fuehrung = v))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _staerkeField(
                              abbr: 'U',
                              label: 'Unterführer',
                              value: _unterfuehrer,
                              onChanged: (v) =>
                                  setState(() => _unterfuehrer = v))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _staerkeField(
                              abbr: 'M',
                              label: 'Mannschaft',
                              value: _mannschaft,
                              onChanged: (v) =>
                                  setState(() => _mannschaft = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Gesamt: ${_fuehrung + _unterfuehrer + _mannschaft}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_selected != null && !_sending) ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Sendet…' : 'Stärke an EDP melden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
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
    );
  }

  Widget _buildCard({required Color cardBg, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: cardBg, borderRadius: BorderRadius.circular(12)),
      child: child,
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.red.shade800),
      );

  Widget _staerkeField({
    required String abbr,
    required String label,
    required int value,
    required void Function(int) onChanged,
  }) {
    return Column(
      children: [
        Text(abbr,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _counterBtn(
                icon: Icons.remove,
                onTap: value > 0 ? () => onChanged(value - 1) : null,
                active: value > 0),
            SizedBox(
              width: 32,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _counterBtn(
                icon: Icons.add,
                onTap: () => onChanged(value + 1),
                active: true),
          ],
        ),
      ],
    );
  }

  Widget _counterBtn(
      {required IconData icon,
      required VoidCallback? onTap,
      required bool active}) {
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
        child: Icon(icon,
            size: 16,
            color: active ? Colors.white : Colors.grey.shade400),
      ),
    );
  }
}
