// lib/data/location_smoother.dart
import 'dart:math';

/// Accuracy-gewichteter 1D-Kalman-Glätter für GPS-Positionen (lat/lon getrennt).
///
/// Reduziert Jitter — vor allem das „Wackeln" im Stand und einzelne leicht
/// verrauschte Fixes — ohne bei Bewegung nennenswert nachzulaufen: Die
/// Prozessvarianz wird aus der aktuellen Geschwindigkeit abgeleitet. Steht das
/// Gerät (speed ~ 0), ist das Prozessrauschen klein → starke Glättung; fährt
/// es schnell, wächst es → der Filter folgt praktisch sofort.
///
/// Angelehnt an das bekannte „KalmanLatLong" (Stochastic Systems / Android).
class LocationSmoother {
  /// Prozessrauschen-Untergrenze in m/s (Glättungsstärke im Stand). Größer =
  /// weniger Glättung, folgt schneller; kleiner = ruhiger, aber träger.
  final double minProcessNoiseMs;

  double? _lat;
  double? _lon;
  double _variance = -1; // <0 = uninitialisiert
  int? _lastTsMs;

  LocationSmoother({this.minProcessNoiseMs = 3.0});

  bool get hasEstimate => _variance >= 0;

  /// Verwirft den bisherigen Schätzwert (z. B. nach einem Resync/Sprung-Reset,
  /// damit nicht über die Korrektur hinweg geglättet wird).
  void reset() {
    _lat = null;
    _lon = null;
    _variance = -1;
    _lastTsMs = null;
  }

  /// Fügt eine Messung hinzu und liefert die geglättete Position samt
  /// verbesserter (kleinerer) Genauigkeit zurück.
  ///
  /// [accuracyM] = gemeldete Genauigkeit (1 Sigma, Meter).
  /// [speedMs]   = aktuelle Geschwindigkeit für die adaptive Prozessvarianz;
  ///               <= 0 bzw. nicht endlich ⇒ als „unbekannt/steht" behandelt.
  ({double lat, double lon, double accuracy}) process({
    required double lat,
    required double lon,
    required double accuracyM,
    required int tsMs,
    double speedMs = -1,
  }) {
    // Genauigkeit auf sinnvollen Bereich klemmen (>= 1 m, endlich).
    final acc = (accuracyM.isFinite && accuracyM > 1.0) ? accuracyM : 1.0;

    if (_variance < 0 || _lat == null || _lon == null) {
      _lat = lat;
      _lon = lon;
      _variance = acc * acc;
      _lastTsMs = tsMs;
      return (lat: lat, lon: lon, accuracy: acc);
    }

    // Zeitschritt in Sekunden, robust gegen Rück-/Nullsprünge der Zeitstempel.
    final dt = _lastTsMs == null ? 0.0 : max(0.0, (tsMs - _lastTsMs!) / 1000.0);
    _lastTsMs = tsMs;

    // Prozessrauschen aus Geschwindigkeit ableiten (mind. minProcessNoiseMs).
    final v = (speedMs.isFinite && speedMs > 0) ? speedMs : 0.0;
    final q = max(minProcessNoiseMs, v);
    _variance += dt * q * q;

    // Kalman-Update: Gewicht der neuen Messung ~ Verhältnis der Varianzen.
    final k = _variance / (_variance + acc * acc);
    _lat = _lat! + k * (lat - _lat!);
    _lon = _lon! + k * (lon - _lon!);
    _variance = (1 - k) * _variance;

    return (lat: _lat!, lon: _lon!, accuracy: sqrt(_variance));
  }
}
