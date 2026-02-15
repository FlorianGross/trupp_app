// lib/map_screen.dart
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'data/location_queue.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _trackPoints = [];
  LatLng? _currentPosition;
  Timer? _refreshTimer;
  bool _followMode = true;

  @override
  void initState() {
    super.initState();
    _loadTrack();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadTrack();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTrack() async {
    try {
      final fixes = await LocationQueue.instance.all();
      if (!mounted) return;

      final points = fixes
          .map((f) => LatLng(f.lat, f.lon))
          .toList();

      // Aktuelle Position holen
      LatLng? current;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          current = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}

      // Fallback: letzter Track-Punkt
      current ??= points.isNotEmpty ? points.last : null;

      setState(() {
        _trackPoints = points;
        _currentPosition = current;
      });

      if (_followMode && current != null) {
        _mapController.move(current, _mapController.camera.zoom);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? Colors.red.shade900 : Colors.red.shade800;

    // Startposition: aktuelle Position oder Deutschland-Mitte
    final center = _currentPosition ?? const LatLng(51.1657, 10.4515);

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Karte'),
        material: (_, _) => MaterialAppBarData(
          backgroundColor: appBarBg,
          elevation: 0,
          centerTitle: true,
        ),
        cupertino: (_, _) => CupertinoNavigationBarData(
          backgroundColor: appBarBg,
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  _followMode = false;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                    : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const ['a', 'b', 'c'],
              ),
              // Track-Linie
              if (_trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints,
                      strokeWidth: 3.0,
                      color: Colors.red.shade700.withOpacity(0.8),
                    ),
                  ],
                ),
              // Aktuelle Position
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade700.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Info-Leiste oben
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey.shade900 : Colors.white).withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.timeline, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '${_trackPoints.length} Punkte',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (_currentPosition != null)
                    Text(
                      '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                      '${_currentPosition!.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Zentrierungs-Button
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () {
                _followMode = true;
                if (_currentPosition != null) {
                  _mapController.move(_currentPosition!, 16);
                }
              },
              backgroundColor: Colors.red.shade800,
              child: Icon(
                _followMode ? Icons.my_location : Icons.location_searching,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
