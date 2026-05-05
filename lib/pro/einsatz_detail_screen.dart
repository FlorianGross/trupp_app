// lib/pro/einsatz_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/edp_api_pro.dart';

class EinsatzDetailScreen extends StatefulWidget {
  final EdpEinsatz einsatz;

  const EinsatzDetailScreen({super.key, required this.einsatz});

  @override
  State<EinsatzDetailScreen> createState() => _EinsatzDetailScreenState();
}

class _EinsatzDetailScreenState extends State<EinsatzDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<EdpVerlaufEintrag>? _verlauf;
  bool _verlaufLoading = false;
  String? _verlaufError;

  List<EdpEinsatzabschnitt>? _abschnitte;
  bool _abschnitteLoading = false;
  String? _abschnitteError;

  List<EdpEinsatzmittel>? _fahrzeuge;
  bool _fahrzeugeLoading = false;
  String? _fahrzeugeError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadVerlauf();
    _loadAbschnitte();
    _loadFahrzeuge();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVerlauf() async {
    final api = EdpApiPro.instance;
    if (api == null) return;
    setState(() {
      _verlaufLoading = true;
      _verlaufError = null;
    });
    final result =
        await api.getEinsatzverlauf(widget.einsatz.einsatznummer);
    if (!mounted) return;
    if (result.ok) {
      final sorted = (result.data ?? [])
        ..sort((a, b) => (b.addTimestamp ?? DateTime(0))
            .compareTo(a.addTimestamp ?? DateTime(0)));
      setState(() {
        _verlauf = sorted;
        _verlaufLoading = false;
      });
    } else {
      setState(() {
        _verlaufError = result.error ?? 'Fehler ${result.statusCode}';
        _verlaufLoading = false;
      });
    }
  }

  Future<void> _loadAbschnitte() async {
    final api = EdpApiPro.instance;
    if (api == null) return;
    setState(() {
      _abschnitteLoading = true;
      _abschnitteError = null;
    });
    final result =
        await api.getEinsatzabschnitte(widget.einsatz.einsatznummer);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _abschnitte = result.data ?? [];
        _abschnitteLoading = false;
      });
    } else {
      setState(() {
        _abschnitteError = result.error ?? 'Fehler ${result.statusCode}';
        _abschnitteLoading = false;
      });
    }
  }

  Future<void> _loadFahrzeuge() async {
    final api = EdpApiPro.instance;
    if (api == null) return;
    setState(() {
      _fahrzeugeLoading = true;
      _fahrzeugeError = null;
    });
    final result = await api.getEinsatzmittel(
        einsatznummer: widget.einsatz.einsatznummer.toString());
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _fahrzeuge = result.data ?? [];
        _fahrzeugeLoading = false;
      });
    } else {
      setState(() {
        _fahrzeugeError = result.error ?? 'Fehler ${result.statusCode}';
        _fahrzeugeLoading = false;
      });
    }
  }

  Future<void> _navigate() async {
    final e = widget.einsatz;
    Uri uri;
    if (e.hasCoordinates) {
      final lat = e.koordy!;
      final lon = e.koordx!;
      final label = Uri.encodeComponent(e.title);
      uri = Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)');
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse('https://maps.google.com/?q=$lat,$lon');
      }
    } else {
      final addr =
          Uri.encodeComponent(e.adresse.isNotEmpty ? e.adresse : e.title);
      uri = Uri.parse('geo:0,0?q=$addr');
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse('https://maps.google.com/?q=$addr');
      }
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.einsatz;
    return Scaffold(
      appBar: AppBar(
        title: Text('#${e.einsatznummer}'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.navigation),
            tooltip: 'Navigation starten',
            onPressed: _navigate,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 20), text: 'Info'),
            Tab(icon: Icon(Icons.history, size: 20), text: 'Verlauf'),
            Tab(
                icon: Icon(Icons.account_tree_outlined, size: 20),
                text: 'Abschnitte'),
            Tab(
                icon: Icon(Icons.fire_truck, size: 20),
                text: 'Fahrzeuge'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(e),
          _buildVerlaufTab(),
          _buildAbschnitteTab(),
          _buildFahrzeugeTab(),
        ],
      ),
    );
  }

  // ─── Info ──────────────────────────────────────────────────────────────────

  Widget _buildInfoTab(EdpEinsatz e) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(title: 'Einsatzdaten', rows: [
          _row('Nr.', '${e.einsatznummer}'),
          if (_notEmpty(e.stichwort)) _row('Stichwort', e.stichwort!),
          if (_notEmpty(e.stichwortKlartext))
            _row('Meldebild', e.stichwortKlartext!),
          if (_notEmpty(e.einsatzart)) _row('Einsatzart', e.einsatzart!),
          if (_notEmpty(e.prioritaet)) _row('Priorität', e.prioritaet!),
          if (_notEmpty(e.status)) _row('Status', e.status!),
        ]),
        const SizedBox(height: 12),
        _infoCard(title: 'Einsatzort', rows: [
          if (e.adresse.isNotEmpty) _row('Adresse', e.adresse),
          if (_notEmpty(e.objektname)) _row('Objekt', e.objektname!),
          if (_notEmpty(e.ortsteil)) _row('Ortsteil', e.ortsteil!),
          if (e.hasCoordinates)
            _row('Koordinaten',
                '${e.koordy!.toStringAsFixed(6)}, ${e.koordx!.toStringAsFixed(6)}'),
        ]),
        const SizedBox(height: 12),
        _infoCard(title: 'Zeitverlauf', rows: [
          if (e.eroeff != null) _row('Eröffnung', _fmtDt(e.eroeff!)),
          if (e.meldungseingang != null)
            _row('Meldungseingang', _fmtDt(e.meldungseingang!)),
          if (_notEmpty(e.meldender)) _row('Meldender', e.meldender!),
        ]),
        if (_notEmpty(e.meldung)) ...[const SizedBox(height: 12), _textCard('Meldung', e.meldung!)],
        if (_notEmpty(e.bemerkung)) ...[const SizedBox(height: 12), _textCard('Bemerkung', e.bemerkung!)],
      ],
    );
  }

  Widget _infoCard({required String title, required List<Widget> rows}) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.red.shade800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _textCard(String title, String text) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.red.shade800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(text,
                style:
                    TextStyle(fontSize: 14, color: Colors.grey.shade800)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ─── Verlauf ───────────────────────────────────────────────────────────────

  Widget _buildVerlaufTab() {
    if (_verlaufLoading)
      return const Center(child: CircularProgressIndicator());
    if (_verlaufError != null)
      return _errorWidget(_verlaufError!, _loadVerlauf);
    final items = _verlauf ?? [];
    if (items.isEmpty) return _emptyWidget('Keine Verlaufeinträge');
    return RefreshIndicator(
      onRefresh: _loadVerlauf,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _buildVerlaufCard(items[i]),
      ),
    );
  }

  Widget _buildVerlaufCard(EdpVerlaufEintrag e) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_notEmpty(e.typ))
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.typ!,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                if (e.addTimestamp != null)
                  Text(_fmtDt(e.addTimestamp!),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
            if (_notEmpty(e.von) || _notEmpty(e.an)) ...
              [
                const SizedBox(height: 6),
                Row(children: [
                  if (_notEmpty(e.von))
                    Text('Von: ${e.von}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  if (_notEmpty(e.von) && _notEmpty(e.an))
                    const SizedBox(width: 12),
                  if (_notEmpty(e.an))
                    Text('An: ${e.an}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                ]),
              ],
            if (_notEmpty(e.eintrag)) ...
              [
                const SizedBox(height: 6),
                Text(e.eintrag!,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            if (_notEmpty(e.auftrag)) ...
              [
                const SizedBox(height: 4),
                Text('Auftrag: ${e.auftrag}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            if (_notEmpty(e.abschnitt)) ...
              [
                const SizedBox(height: 4),
                Text('Abschnitt: ${e.abschnitt}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
          ],
        ),
      ),
    );
  }

  // ─── Abschnitte ────────────────────────────────────────────────────────────

  Widget _buildAbschnitteTab() {
    if (_abschnitteLoading)
      return const Center(child: CircularProgressIndicator());
    if (_abschnitteError != null)
      return _errorWidget(_abschnitteError!, _loadAbschnitte);
    final items = _abschnitte ?? [];
    if (items.isEmpty) return _emptyWidget('Keine Abschnitte vorhanden');
    return RefreshIndicator(
      onRefresh: _loadAbschnitte,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _buildAbschnittCard(items[i]),
      ),
    );
  }

  Widget _buildAbschnittCard(EdpEinsatzabschnitt a) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined,
                    color: Colors.red.shade800, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notEmpty(a.bezeichnung)
                        ? a.bezeichnung!
                        : 'Abschnitt ${a.id}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            if (_notEmpty(a.eal)) ...[const SizedBox(height: 6), _row('EAL', a.eal!)],
            if (_notEmpty(a.kanal)) _row('Kanal', a.kanal!),
            if (_notEmpty(a.rufname)) _row('Rufname', a.rufname!),
            if (_notEmpty(a.zusatz)) _row('Zusatz', a.zusatz!),
          ],
        ),
      ),
    );
  }

  // ─── Fahrzeuge ─────────────────────────────────────────────────────────────

  Widget _buildFahrzeugeTab() {
    if (_fahrzeugeLoading)
      return const Center(child: CircularProgressIndicator());
    if (_fahrzeugeError != null)
      return _errorWidget(_fahrzeugeError!, _loadFahrzeuge);
    final items = _fahrzeuge ?? [];
    if (items.isEmpty) return _emptyWidget('Keine Fahrzeuge zugewiesen');
    return RefreshIndicator(
      onRefresh: _loadFahrzeuge,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _buildFahrzeugCard(items[i]),
      ),
    );
  }

  Widget _buildFahrzeugCard(EdpEinsatzmittel f) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.fire_truck,
                  color: Colors.red.shade800, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.rufname,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (_notEmpty(f.rufnameLang))
                    Text(f.rufnameLang!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  if (_notEmpty(f.abschnitt))
                    Text(f.abschnitt!,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_notEmpty(f.status))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(f.status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(f.status!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _statusColor(f.status),
                            fontWeight: FontWeight.bold)),
                  ),
                if (f.besatzungGes != null && f.besatzungGes! > 0) ...
                  [
                    const SizedBox(height: 4),
                    Text('${f.besatzungGes} Pers.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Color _statusColor(String? status) {
    switch (status) {
      case '1':
      case '2':
        return Colors.green;
      case '3':
      case '4':
        return Colors.orange;
      case '5':
        return Colors.blue;
      case '6':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _notEmpty(String? s) => s != null && s.isNotEmpty;

  Widget _errorWidget(String msg, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: retry,
                child: const Text('Erneut versuchen')),
          ],
        ),
      ),
    );
  }

  Widget _emptyWidget(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  String _fmtDt(DateTime dt) {
    final l = dt.toLocal();
    final d =
        '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
    final t =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }
}
