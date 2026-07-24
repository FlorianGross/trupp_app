// lib/map_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'data/location_queue.dart';
import 'utils/formatters.dart';

enum _MapMode { live, replay }

class MapScreen extends StatefulWidget {
  /// Optionaler Zeitbereich für direktes Einsatz-Replay.
  final int? replayFromMs;
  final int? replayToMs;

  const MapScreen({super.key, this.replayFromMs, this.replayToMs});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  // Live-Modus
  List<LatLng> _trackPoints = [];
  LatLng? _currentPosition;
  Timer? _refreshTimer;
  bool _followMode = true;

  // Modus
  _MapMode _mode = _MapMode.live;

  // Replay-Modus.
  //
  // Der Replay-Index läuft über einen ValueNotifier statt setState: der
  // Timer tickt mit bis zu 60 Hz, und ein setState pro Tick würde den
  // kompletten Screen (inkl. TileLayer) neu bauen. So bauen nur die
  // kleinen ValueListenableBuilder-Subtrees (Trail, Marker, Infozeile,
  // Slider) neu.
  final ValueNotifier<int> _replayIndex = ValueNotifier<int>(0);
  bool _replayPlaying = false;
  int _replaySpeed = 10;
  Timer? _replayTimer;
  List<LocationFix> _replayFixes = [];

  static const _speedOptions = [1, 5, 10, 30, 60];

  @override
  void initState() {
    super.initState();
    if (widget.replayFromMs != null) {
      _mode = _MapMode.replay;
      _loadReplayTrack();
    } else {
      _loadTrack();
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadTrack());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _replayTimer?.cancel();
    _replayIndex.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ─── Live ─────────────────────────────────────────────────────────────────

  Future<void> _loadTrack() async {
    try {
      final fixes = await LocationQueue.instance.all();
      if (!mounted) return;
      final points = fixes.map((f) => LatLng(f.lat, f.lon)).toList();
      LatLng? current;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) current = LatLng(pos.latitude, pos.longitude);
      } catch (_) {}
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

  // ─── Replay ───────────────────────────────────────────────────────────────

  Future<void> _loadReplayTrack() async {
    try {
      final List<LocationFix> fixes;
      if (widget.replayFromMs != null && widget.replayToMs != null) {
        fixes = await LocationQueue.instance
            .byTimeRange(fromMs: widget.replayFromMs!, toMs: widget.replayToMs!);
      } else {
        fixes = await LocationQueue.instance.all();
      }
      if (!mounted) return;
      _replayIndex.value = 0;
      setState(() {
        _replayFixes = fixes;
        _trackPoints = fixes.map((f) => LatLng(f.lat, f.lon)).toList();
      });
      if (fixes.isNotEmpty) {
        _mapController.move(LatLng(fixes.first.lat, fixes.first.lon), 15);
      }
    } catch (_) {}
  }

  void _replayPlayPause() {
    if (_replayFixes.isEmpty) return;
    if (_replayPlaying) {
      _replayTimer?.cancel();
      setState(() => _replayPlaying = false);
    } else {
      if (_replayIndex.value >= _replayFixes.length - 1) {
        _replayIndex.value = 0;
      }
      setState(() => _replayPlaying = true);
      _startReplayTimer();
    }
  }

  void _startReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _replaySpeed).round()),
      (_) {
        if (!mounted) return;
        if (_replayIndex.value < _replayFixes.length - 1) {
          // Kein setState — nur der Notifier triggert die kleinen Subtrees.
          _replayIndex.value++;
          final fix = _replayFixes[_replayIndex.value];
          _mapController.move(LatLng(fix.lat, fix.lon), _mapController.camera.zoom);
        } else {
          _replayTimer?.cancel();
          setState(() => _replayPlaying = false);
        }
      },
    );
  }

  void _onReplaySliderChanged(double value) {
    final idx = value.round().clamp(0, (_replayFixes.length - 1).clamp(0, 999999));
    _replayIndex.value = idx;
    if (_replayFixes.isNotEmpty) {
      final fix = _replayFixes[idx];
      _mapController.move(LatLng(fix.lat, fix.lon), _mapController.camera.zoom);
    }
    if (_replayPlaying) {
      _replayTimer?.cancel();
      _startReplayTimer();
    }
  }

  void _cycleSpeed() {
    final next = _speedOptions[(_speedOptions.indexOf(_replaySpeed) + 1) % _speedOptions.length];
    setState(() => _replaySpeed = next);
    if (_replayPlaying) {
      _replayTimer?.cancel();
      _startReplayTimer();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition ?? const LatLng(51.1657, 10.4515);
    final isReplay = _mode == _MapMode.replay;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Karte'),
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              _replayTimer?.cancel();
              final goingReplay = _mode == _MapMode.live;
              _replayIndex.value = 0;
              setState(() {
                _mode = goingReplay ? _MapMode.replay : _MapMode.live;
                _replayPlaying = false;
              });
              if (goingReplay) {
                _loadReplayTrack();
              } else {
                _refreshTimer?.cancel();
                _loadTrack();
                _refreshTimer =
                    Timer.periodic(const Duration(seconds: 10), (_) => _loadTrack());
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(isReplay ? 'Live' : 'Replay'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && !isReplay) _followMode = false;
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains:
                const ['a', 'b', 'c'],
                userAgentPackageName: 'de.floriang.trupp_app',
              ),
              // Vollständiger Track im Replay gedimmt
              if (isReplay && _trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints,
                      strokeWidth: 2.0,
                      color: Colors.grey.withOpacity(0.3),
                    ),
                  ],
                ),
              if (isReplay)
                ValueListenableBuilder<int>(
                  valueListenable: _replayIndex,
                  builder: (_, idx, __) {
                    if (idx < 1 || _trackPoints.length < 2) {
                      return const SizedBox.shrink();
                    }
                    return PolylineLayer(
                      polylines: [
                        Polyline(
                          // Trail als Sublist des gecachten Tracks — keine
                          // Neuberechnung der LatLng-Objekte pro Tick.
                          points: _trackPoints.sublist(0, idx + 1),
                          strokeWidth: 3.0,
                          color: Colors.blue.shade600.withOpacity(0.85),
                        ),
                      ],
                    );
                  },
                )
              else if (_trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints,
                      strokeWidth: 3.0,
                      color: Colors.red.shade700.withOpacity(0.85),
                    ),
                  ],
                ),
              if (isReplay)
                ValueListenableBuilder<int>(
                  valueListenable: _replayIndex,
                  builder: (_, idx, __) {
                    if (_replayFixes.isEmpty) return const SizedBox.shrink();
                    final fix = _replayFixes[idx.clamp(0, _replayFixes.length - 1)];
                    return MarkerLayer(
                      markers: [_positionMarker(LatLng(fix.lat, fix.lon), replay: true)],
                    );
                  },
                )
              else if (_currentPosition != null)
                MarkerLayer(
                  markers: [_positionMarker(_currentPosition!, replay: false)],
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
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    isReplay ? Icons.play_circle_outline : Icons.timeline,
                    size: 16,
                    color: isReplay ? Colors.blue.shade600 : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  if (isReplay)
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _replayIndex,
                        builder: (_, idx, __) => Row(
                          children: [
                            Text(
                              '${idx + 1} / ${_replayFixes.length} Punkte',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (_replayFixes.isNotEmpty)
                              Text(
                                fmtTimeFromMs(_replayFixes[
                                        idx.clamp(0, _replayFixes.length - 1)]
                                    .tsMs),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      '${_trackPoints.length} Punkte',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (_currentPosition != null)
                      Text(
                        '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                        '${_currentPosition!.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Replay-Panel unten
          if (isReplay) _buildReplayPanel(),

          // Zentrierungs-Button (nur Live)
          if (!isReplay)
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

  Marker _positionMarker(LatLng point, {required bool replay}) {
    return Marker(
      point: point,
      width: 24,
      height: 24,
      child: Container(
        decoration: BoxDecoration(
          color: replay ? Colors.blue.shade600 : Colors.red.shade700,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: (replay ? Colors.blue : Colors.red.shade700).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplayPanel() {
    final bg = Theme.of(context).colorScheme.surface;
    final hasData = _replayFixes.isNotEmpty;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasData)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.blue.shade600,
                  thumbColor: Colors.blue.shade600,
                  inactiveTrackColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _replayIndex,
                  builder: (_, idx, __) => Slider(
                    value: idx.toDouble(),
                    min: 0,
                    max: (_replayFixes.length - 1).toDouble().clamp(0, double.infinity),
                    onChanged: _onReplaySliderChanged,
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: hasData
                      ? () {
                          _replayTimer?.cancel();
                          _replayIndex.value = 0;
                          setState(() => _replayPlaying = false);
                          if (_replayFixes.isNotEmpty) {
                            _mapController.move(
                              LatLng(_replayFixes.first.lat, _replayFixes.first.lon),
                              _mapController.camera.zoom,
                            );
                          }
                        }
                      : null,
                  color: Colors.blue.shade600,
                  iconSize: 28,
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: hasData ? _replayPlayPause : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: Icon(
                    _replayPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: hasData
                      ? () {
                          _replayTimer?.cancel();
                          _replayIndex.value = _replayFixes.length - 1;
                          setState(() => _replayPlaying = false);
                          if (_replayFixes.isNotEmpty) {
                            _mapController.move(
                              LatLng(_replayFixes.last.lat, _replayFixes.last.lon),
                              _mapController.camera.zoom,
                            );
                          }
                        }
                      : null,
                  color: Colors.blue.shade600,
                  iconSize: 28,
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _cycleSpeed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                    side: BorderSide(color: Colors.blue.shade600),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '${_replaySpeed}×',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
