// lib/pro/issi_picker_screen.dart
import 'package:flutter/material.dart';
import '../data/edp_api_pro.dart';

class IssiPickerScreen extends StatefulWidget {
  const IssiPickerScreen({super.key});

  @override
  State<IssiPickerScreen> createState() => _IssiPickerScreenState();
}

class _IssiPickerScreenState extends State<IssiPickerScreen> {
  List<EdpTetraEndgeraet> _all = [];
  List<EdpTetraEndgeraet> _filtered = [];
  bool _loading = true;
  String? _error;
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
      _error = null;
    });
    final api = EdpApiPro.instance;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'Pro-API nicht initialisiert.';
      });
      return;
    }
    final result = await api.getTetraEndgeraete();
    if (!mounted) return;
    if (result.ok) {
      final items = (result.data ?? [])
        ..sort((a, b) =>
            (a.rufname ?? a.issi).compareTo(b.rufname ?? b.issi));
      setState(() {
        _all = items;
        _filtered = items;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error ?? 'Fehler ${result.statusCode}';
      });
    }
  }

  void _onSearch(String q) {
    setState(() {
      if (q.isEmpty) {
        _filtered = _all;
      } else {
        final lower = q.toLowerCase();
        _filtered = _all
            .where((g) =>
                g.issi.toLowerCase().contains(lower) ||
                (g.rufname?.toLowerCase().contains(lower) ?? false) ||
                (g.opta?.toLowerCase().contains(lower) ?? false))
            .toList();
      }
    });
  }

  static String _typeLabel(int t) {
    const labels = {
      0: 'Unbekannt',
      1: 'FRT',
      2: 'MRT',
      3: 'HRT',
      4: 'APRT',
      5: 'Rescue-Track',
      6: 'GPS-Tracker',
      7: 'Sirene',
    };
    return labels[t] ?? 'Typ $t';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ISSI auswählen'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ISSI, Rufname oder OPTA suchen…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        })
                    : null,
              ),
            ),
          ),
          if (!_loading && _error == null)
            Padding(
              padding:
                  const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} Gerät${_filtered.length != 1 ? 'e' : ''}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
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
        child: Text('Keine Geräte gefunden',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final g = _filtered[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.red.shade50,
            child:
                Icon(Icons.radio, color: Colors.red.shade800, size: 20),
          ),
          title: Text(g.rufname ?? g.issi,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              g.issi,
              if (g.opta != null && g.opta!.isNotEmpty) g.opta!,
              _typeLabel(g.type),
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(g.issi),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      },
    );
  }
}
