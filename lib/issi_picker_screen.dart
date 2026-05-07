// lib/issi_picker_screen.dart
//
// ISSI-Picker für das Onboarding – alle Abfragen über EdpApiPro mit
// Standard-Zugangsdaten (trupp_app).
import 'package:flutter/material.dart';
import 'data/edp_api.dart';
import 'data/edp_api_pro.dart';

enum _PickerTab { tetra, einsatzmittel }

class IssiPickerScreenAnonymous extends StatefulWidget {
  const IssiPickerScreenAnonymous({super.key});

  @override
  State<IssiPickerScreenAnonymous> createState() =>
      _IssiPickerScreenAnonymousState();
}

class _IssiPickerScreenAnonymousState
    extends State<IssiPickerScreenAnonymous>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  List<EdpTetraEndgeraet> _tetraAll = [];
  List<EdpTetraEndgeraet> _tetraFiltered = [];
  List<EdpEinsatzmittel> _emAll = [];
  List<EdpEinsatzmittel> _emFiltered = [];

  bool _loading = true;
  String? _error;
  bool _poolOnly = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<EdpApiPro?> _ensureApi() async {
    EdpApiPro? api = EdpApiPro.instance;
    if (api != null) return api;
    try {
      api = await EdpApiPro.initFromPrefs();
    } catch (_) {}
    return api;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = await _ensureApi();
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'EDP-Pro-API nicht konfiguriert.\n'
            'Bitte EDP-Pro-API-URL in den Einstellungen angeben.';
      });
      return;
    }

    try {
      final results = await Future.wait([
        api.getTetraEndgeraete(),
        api.getEinsatzmittel(),
      ]);

      if (!mounted) return;

      final tetraResult = results[0] as EdpProResult<List<EdpTetraEndgeraet>>;
      final emResult = results[1] as EdpProResult<List<EdpEinsatzmittel>>;

      if (!tetraResult.ok && !emResult.ok) {
        setState(() {
          _loading = false;
          _error =
              'Server nicht erreichbar (${tetraResult.error ?? emResult.error})';
        });
        return;
      }

      final tetraItems = (tetraResult.data ?? [])
        ..sort((a, b) =>
            (a.rufname ?? a.issi).compareTo(b.rufname ?? b.issi));
      final emItems = (emResult.data ?? [])
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

      setState(() {
        _tetraAll = tetraItems;
        _emAll = emItems;
        _loading = false;
        _applyFilters();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _applyFilters() {
    final q = _searchCtrl.text.toLowerCase();
    var tetra = _poolOnly ? _tetraAll.where((g) => g.isPool).toList() : _tetraAll.toList();
    if (q.isNotEmpty) {
      tetra = tetra
          .where((g) =>
              g.issi.toLowerCase().contains(q) ||
              (g.rufname?.toLowerCase().contains(q) ?? false) ||
              (g.opta?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    _tetraFiltered = tetra;

    _emFiltered = q.isEmpty
        ? _emAll
        : _emAll
            .where((e) =>
                e.rufname.toLowerCase().contains(q) ||
                (e.rufnameLang?.toLowerCase().contains(q) ?? false) ||
                (e.wache?.toLowerCase().contains(q) ?? false))
            .toList();
  }

  void _onSearch(String q) => setState(_applyFilters);

  void _togglePoolOnly(bool? v) {
    setState(() {
      _poolOnly = v ?? true;
      _applyFilters();
    });
  }

  static String _tetraTypeLabel(int t) {
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
    final isTetraTab = _tabCtrl.index == 0;
    final count = isTetraTab ? _tetraFiltered.length : _emFiltered.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ISSI / Einheit auswählen'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
            tooltip: 'Neu laden',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.radio_rounded, size: 18), text: 'TETRA-Geräte'),
            Tab(icon: Icon(Icons.directions_car_rounded, size: 18), text: 'Einsatzmittel'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: isTetraTab
                    ? 'ISSI, Rufname oder OPTA suchen…'
                    : 'Rufname oder Wache suchen…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      )
                    : null,
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
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$count Eintr${count != 1 ? 'äge' : 'ag'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _buildTetraList(),
                          _buildEinsatzmittelList(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Verbindung fehlgeschlagen',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Erneut versuchen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTetraList() {
    final poolCount = _tetraAll.where((g) => g.isPool).length;
    return Column(
      children: [
        if (poolCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Checkbox(
                  value: _poolOnly,
                  onChanged: _togglePoolOnly,
                  activeColor: Colors.red.shade800,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _togglePoolOnly(!_poolOnly),
                    child: Text(
                      'Nur Pool-Geräte ($poolCount)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _tetraFiltered.isEmpty
              ? Center(
                  child: Text(
                    _tetraAll.isEmpty
                        ? 'Keine TETRA-Geräte gefunden'
                        : _poolOnly
                            ? 'Keine Pool-Geräte gefunden'
                            : 'Keine Treffer für "${_searchCtrl.text}"',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: _tetraFiltered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final g = _tetraFiltered[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        child: Icon(Icons.radio_rounded,
                            color: Colors.red.shade800, size: 20),
                      ),
                      title: Text(
                        g.rufname ?? g.issi,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          g.issi,
                          if (g.opta != null && g.opta!.isNotEmpty) g.opta!,
                          _tetraTypeLabel(g.type),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).pop(g.issi),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEinsatzmittelList() {
    if (_emFiltered.isEmpty) {
      return Center(
        child: Text(
          _emAll.isEmpty
              ? 'Keine Einsatzmittel gefunden'
              : 'Keine Treffer für "${_searchCtrl.text}"',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: _emFiltered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final em = _emFiltered[i];
        final statusColor = _emStatusColor(em.status);
        return ListTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          leading: CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(Icons.directions_car_rounded,
                color: statusColor, size: 20),
          ),
          title: Text(
            em.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              if (em.status != null && em.status!.isNotEmpty)
                'Status ${em.status}',
              if (em.wache != null && em.wache!.isNotEmpty) em.wache!,
              if (em.typ != null && em.typ!.isNotEmpty) em.typ!,
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (em.rufname.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    em.rufname,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: () => Navigator.of(context).pop(em.rufname),
        );
      },
    );
  }

  Color _emStatusColor(String? status) {
    switch (status) {
      case '1': return Colors.green;
      case '2': return Colors.blue;
      case '3': return Colors.orange;
      case '4': return Colors.purple;
      case '5': return Colors.teal;
      case '6': return Colors.red;
      case '7': return Colors.grey;
      case '8': return Colors.cyan;
      case '9': return Colors.red.shade900;
      default:  return Colors.grey;
    }
  }
}
