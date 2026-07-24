// lib/pro/fahrzeug_karte_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/edp_api.dart';
import '../data/edp_api_pro.dart';
import '../theme/em_status.dart';
import '../utils/formatters.dart';

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

  // Marker werden NICHT im build() erzeugt, sondern nur wenn sich Daten
  // oder (für das Clustering relevant) die Zoom-Stufe ändern. Das vermeidet
  // den kompletten Marker-Neuaufbau bei jedem Rebuild des Screens.
  List<Marker> _markers = [];
  int _lastClusterZoom = -1;
  StreamSubscription<MapEvent>? _mapEvtSub;

  /// Ab dieser Fahrzeugzahl werden nahe Marker zu Clustern zusammengefasst —
  /// sonst überlappen sie und sind nicht mehr antippbar.
  static const _clusterThreshold = 20;

  static const _defaultCenter = LatLng(51.1657, 10.4515);
  static const _defaultZoom = 6.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapEvtSub?.cancel();
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
        _rebuildMarkers();
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

  // ─── Marker & Clustering ────────────────────────────────────────────────

  void _onMapReady() {
    _lastClusterZoom = _mapController.camera.zoom.round();
    // Cluster nur bei Zoom-Änderung neu berechnen (nicht bei jedem Pan).
    _mapEvtSub = _mapController.mapEventStream.listen((evt) {
      if (evt is! MapEventMoveEnd && evt is! MapEventDoubleTapZoomEnd) return;
      final zoom = _mapController.camera.zoom.round();
      if (zoom == _lastClusterZoom) return;
      _lastClusterZoom = zoom;
      if (_mitPosition.length > _clusterThreshold && mounted) {
        setState(_rebuildMarkers);
      }
    });
  }

  void _rebuildMarkers() {
    if (_mitPosition.length <= _clusterThreshold) {
      _markers = _mitPosition.map(_vehicleMarker).toList();
      return;
    }

    // Einfaches Grid-Clustering: Fahrzeuge in Zellen von ~½ Kachelbreite
    // der aktuellen Zoom-Stufe gruppieren. Zelle mit 1 Fahrzeug → normaler
    // Marker, mehrere → Cluster-Bubble mit Anzahl (Tap zoomt hinein).
    final zoom = _lastClusterZoom < 0 ? _defaultZoom.round() : _lastClusterZoom;
    final cellDeg = 360.0 / math.pow(2, zoom) / 2.0;

    final cells = <String, List<EdpEinsatzmittel>>{};
    for (final em in _mitPosition) {
      final key =
          '${(em.koordY! / cellDeg).floor()}_${(em.koordX! / cellDeg).floor()}';
      cells.putIfAbsent(key, () => []).add(em);
    }

    _markers = cells.values.map((group) {
      if (group.length == 1) return _vehicleMarker(group.first);
      return _clusterMarker(group);
    }).toList();
  }

  Marker _vehicleMarker(EdpEinsatzmittel em) {
    final color = emStatusColor(em.status);
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
              border: Border.all(color: Colors.white, width: 2),
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
  }

  Marker _clusterMarker(List<EdpEinsatzmittel> group) {
    // Schwerpunkt der Gruppe als Marker-Position
    final lat = group.map((e) => e.koordY!).reduce((a, b) => a + b) / group.length;
    final lon = group.map((e) => e.koordX!).reduce((a, b) => a + b) / group.length;
    return Marker(
      point: LatLng(lat, lon),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () {
          final coords = group.map((e) => LatLng(e.koordY!, e.koordX!)).toList();
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(coords),
              padding: const EdgeInsets.all(60),
              maxZoom: 16,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade800,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${group.length}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
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
                      color: emStatusColor(em.status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Status ${em.status}',
                      style: TextStyle(
                          color: emStatusColor(em.status),
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
              _infoRow('Letzte Meldung', fmtDateTimeShort(em.zeitstempel!)),
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
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
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
                      options: MapOptions(
                        initialCenter: _defaultCenter,
                        initialZoom: _defaultZoom,
                        onMapReady: _onMapReady,
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
                        MarkerLayer(markers: _markers),
                      ],
                    ),
                    if (_mitPosition.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Keine Fahrzeuge mit GPS-Daten',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
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
