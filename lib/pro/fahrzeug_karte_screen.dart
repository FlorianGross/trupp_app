// lib/pro/fahrzeug_karte_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/edp_api.dart';
import '../data/edp_api_pro.dart';

class FahrzeugKarteScreen extends StatefulWidget {
  const FahrzeugKarteScreen({super.key});

  @override
  State<FahrzeugKarteScreen> createState() => _FahrzeugKarteScreenState();
}

class _FahrzeugKarteScreenState extends State<FahrzeugKarteScreen> {
  final MapController _mapController = MapController();
  List<EdpEinsatzmittel> _alle = [];
  List<EdpEinsatzmittel> _mitPosition = [];
  bool _loading = true;
  String? _error;

  static const _defaultCenter = LatLng(51.1657, 10.4515);
  static const _defaultZoom = 6.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapController.dispose();
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
        _error = 'Nicht angemeldet';
      });
      return;
    }
    final result = await api.getEinsatzmittel();
    if (!mounted) return;
    if (result.ok) {
      final all = result.data ?? [];
      final withPos = all.where((e) => e.hasCoordinates).toList();
      setState(() {
        _alle = all;
        _mitPosition = withPos;
        _loading = false;
      });
      _fitBounds();
    } else {
      setState(() {
        _error = result.error ?? 'Fehler ${result.statusCode}';
        _loading = false;
      });
    }
  }

  void _fitBounds() {
    if (_mitPosition.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final coords =
          _mitPosition.map((e) => LatLng(e.koordY!, e.koordX!)).toList();
      if (coords.length == 1) {
        _mapController.move(coords.first, 14);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(coords),
            padding: const EdgeInsets.all(50),
          ),
        );
      }
    });
  }

  Color _markerColor(String? status) {
    switch (status) {
      case '1':
      case '2':
        return Colors.green.shade600;
      case '3':
      case '4':
        return Colors.orange.shade600;
      case '5':
        return Colors.blue.shade600;
      case '6':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  void _showVehicleInfo(EdpEinsatzmittel em) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fire_truck, color: Colors.red.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    em.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (em.status != null && em.status!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _markerColor(em.status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Status ${em.status}',
                      style: TextStyle(
                          color: _markerColor(em.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (em.typ != null && em.typ!.isNotEmpty)
              _infoRow('Typ', em.typ!),
            if (em.wache != null && em.wache!.isNotEmpty)
              _infoRow('Wache', em.wache!),
            if (em.einsatz != null && em.einsatz!.isNotEmpty)
              _infoRow('Einsatz', em.einsatz!),
            if (em.abschnitt != null && em.abschnitt!.isNotEmpty)
              _infoRow('Abschnitt', em.abschnitt!),
            if (em.besatzungGes != null && em.besatzungGes! > 0)
              _infoRow('Besatzung', '${em.besatzungGes} Personen'),
            if (em.zeitstempel != null)
              _infoRow('Letzte Meldung', _fmtDt(em.zeitstempel!)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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

  String _fmtDt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading
            ? 'Fahrzeugkarte'
            : '${_mitPosition.length} / ${_alle.length} Fahrzeuge'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Aktualisieren',
            ),
          if (!_loading && _mitPosition.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.center_focus_strong),
              onPressed: _fitBounds,
              tooltip: 'Alle anzeigen',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(
                        initialCenter: _defaultCenter,
                        initialZoom: _defaultZoom,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: isDark
                              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: isDark
                              ? const ['a', 'b', 'c', 'd']
                              : const ['a', 'b', 'c'],
                          userAgentPackageName: 'de.floriang.trupp_app',
                        ),
                        MarkerLayer(
                          markers: _mitPosition.map((em) {
                            final color = _markerColor(em.status);
                            return Marker(
                              point: LatLng(em.koordY!, em.koordX!),
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () => _showVehicleInfo(em),
                                child: Tooltip(
                                  message: em.displayName,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.4),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        em.status ?? '?',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    if (_mitPosition.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Keine Fahrzeuge mit GPS-Daten',
                            style:
                                TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _buildLegend(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(Colors.green.shade600, 'Verfügbar (1/2)'),
          _legendItem(Colors.orange.shade600, 'Im Einsatz (3/4)'),
          _legendItem(Colors.blue.shade600, 'Sprechwunsch (5)'),
          _legendItem(Colors.red.shade700, 'N.E.B. (6)'),
          _legendItem(Colors.grey.shade600, 'Unbekannt'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
