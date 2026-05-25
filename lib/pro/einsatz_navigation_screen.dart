// lib/pro/einsatz_navigation_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/edp_api_pro.dart';
import 'einsatz_detail_screen.dart';

class EinsatzNavigationScreen extends StatefulWidget {
  const EinsatzNavigationScreen({super.key});

  @override
  State<EinsatzNavigationScreen> createState() =>
      _EinsatzNavigationScreenState();
}

class _EinsatzNavigationScreenState
    extends State<EinsatzNavigationScreen> {
  List<EdpEinsatz> _einsaetze = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = EdpApiPro.instance;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'Pro-API nicht initialisiert. Bitte zuerst anmelden.';
      });
      return;
    }
    final result = await api.getEinsaetze();
    if (!mounted) return;
    if (result.ok) {
      final all = result.data ?? [];
      final active = all
          .where((e) =>
              e.aktiv != null && e.aktiv!.isNotEmpty && e.aktiv != '0')
          .toList();
      setState(() {
        _einsaetze = active.isNotEmpty ? active : all;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error ?? 'Fehler ${result.statusCode}';
      });
    }
  }

  List<EdpEinsatz> get _filtered {
    if (_filter.isEmpty) return _einsaetze;
    final q = _filter.toLowerCase();
    return _einsaetze
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.adresse.toLowerCase().contains(q) ||
            '${e.einsatznummer}'.contains(q))
        .toList();
  }

  Future<void> _navigate(EdpEinsatz e) async {
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
      final addr = Uri.encodeComponent(
          e.adresse.isNotEmpty ? e.adresse : e.title);
      uri = Uri.parse('geo:0,0?q=$addr');
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse('https://maps.google.com/?q=$addr');
      }
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openDetail(EdpEinsatz e) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => EinsatzDetailScreen(einsatz: e)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsätze'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v),
              decoration: InputDecoration(
                hintText: 'Suchen…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _load,
                  child: const Text('Erneut versuchen')),
            ],
          ),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _filter.isEmpty
                  ? 'Keine aktiven Einsätze'
                  : 'Keine Ergebnisse für "$_filter"',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  Widget _buildCard(EdpEinsatz e) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(e),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.local_fire_department,
                    color: Colors.red.shade800, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                        ),
                        if (e.prioritaet != null &&
                            e.prioritaet!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              e.prioritaet!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    if (e.adresse.isNotEmpty) ...
                      [
                        const SizedBox(height: 4),
                        Text(e.adresse,
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700)),
                      ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('#${e.einsatznummer}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                        if (e.eroeff != null) ...
                          [
                            const SizedBox(width: 8),
                            Text(_fmtTime(e.eroeff!),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500)),
                          ],
                        const Spacer(),
                        // Navigation icon button
                        GestureDetector(
                          onTap: () => _navigate(e),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.hasCoordinates
                                    ? Icons.navigation
                                    : Icons.location_searching,
                                size: 16,
                                color: e.hasCoordinates
                                    ? Colors.red.shade800
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Navigation',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: e.hasCoordinates
                                        ? Colors.red.shade800
                                        : Colors.grey.shade400,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')} Uhr';
  }
}
