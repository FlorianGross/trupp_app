// lib/data/location_smoother.dart
import 'dart:math';

/// Genauigkeits-Pipeline für GPS-Positionen:
///   1) Stillstands-Anker: steht das Gerät, wird die Position „eingefroren"
///      (laufender Mittelwert), damit sie nicht driftet/zappelt,
///   2) 2D-Constant-Velocity-Kalman (pro Achse) mit Beschleunigungs-
///      Prozessrauschen und der gemeldeten Genauigkeit als Messrauschen —
///      folgt Bewegung ohne nennenswertes Nachlaufen und glättet Jitter,
///   3) Ausreißer-Verwerfung per Innovations-Gating: ein Fix, der mit der
///      geschätzten Bewegung unvereinbar ist (Spike), wird übersprungen
///      (der Filter coastet kurz auf der Prädiktion) — begrenzt, damit er
///      nach echten Sprüngen wieder aufsetzt. Das ersetzt einen naiven
///      Median-Vorfilter, der bei schneller Fahrt nachlaufen würde.
///
/// Intern wird in lokalen Metern relativ zu einem Referenzpunkt gerechnet
/// (equirektangulär), was für Einsatz-Distanzen genau genug ist.
class LocationSmoother {
  /// Beschleunigungs-Standardabweichung (m/s²) = Prozessrauschen des CV-Modells.
  /// Größer → folgt schneller/weniger Glättung; kleiner → ruhiger/träger.
  final double accelStd;

  /// Unter dieser Geschwindigkeit (m/s) gilt das Gerät als stehend.
  final double stationarySpeed;

  /// Springt die Rohposition weiter als das vom Anker weg, gilt es trotz
  /// niedriger Geschwindigkeit als Bewegung (Anker lösen).
  final double anchorReleaseM;

  /// Mahalanobis-Schwelle fürs Innovations-Gating (Ausreißer-Verwerfung).
  final double outlierGate;

  /// Nach so vielen aufeinanderfolgenden Ausreißern wird der Fix trotzdem
  /// akzeptiert (Wiederaufsetzen nach echtem Sprung).
  final int maxSkips;

  static const double _mPerDegLat = 111320.0;
  double _mPerDegLon = 111320.0;
  double? _lat0, _lon0; // Referenzpunkt

  late final _Kf1d _kx; // Ost (x)
  late final _Kf1d _ky; // Nord (y)

  bool _stationary = false;
  double? _anchorLat, _anchorLon;
  int _anchorN = 0;
  int _skips = 0;
  int? _lastTsMs;

  LocationSmoother({
    this.accelStd = 2.0,
    this.stationarySpeed = 0.7,
    this.anchorReleaseM = 20.0,
    this.outlierGate = 4.0,
    this.maxSkips = 3,
  }) {
    _kx = _Kf1d(accelStd * accelStd);
    _ky = _Kf1d(accelStd * accelStd);
  }

  bool get hasEstimate => _lat0 != null;

  void reset() {
    _lat0 = null;
    _lon0 = null;
    _kx.reset();
    _ky.reset();
    _stationary = false;
    _anchorLat = null;
    _anchorLon = null;
    _anchorN = 0;
    _skips = 0;
    _lastTsMs = null;
  }

  ({double lat, double lon, double accuracy}) process({
    required double lat,
    required double lon,
    required double accuracyM,
    required int tsMs,
    double speedMs = -1,
  }) {
    final acc = (accuracyM.isFinite && accuracyM > 1.0) ? accuracyM : 1.0;
    final measVar = acc * acc;

    // Erster Fix: Referenz + Filter initialisieren.
    if (_lat0 == null) {
      _lat0 = lat;
      _lon0 = lon;
      _mPerDegLon = _mPerDegLat * cos(lat * pi / 180.0);
      _kx.init(0, measVar);
      _ky.init(0, measVar);
      _anchorLat = lat;
      _anchorLon = lon;
      _anchorN = 1;
      _stationary = true;
      _lastTsMs = tsMs;
      return (lat: lat, lon: lon, accuracy: acc);
    }

    final dt = max(0.0, (tsMs - (_lastTsMs ?? tsMs)) / 1000.0);
    _lastTsMs = tsMs;

    // Stillstands-Erkennung: Geschwindigkeit (falls bekannt) oder KF-Velocity.
    final movedFromAnchor = _anchorLat == null
        ? 0.0
        : _distM(lat, lon, _anchorLat!, _anchorLon!);
    final vEst = sqrt(_kx.v * _kx.v + _ky.v * _ky.v);
    final slow = (speedMs.isFinite && speedMs >= 0)
        ? speedMs < stationarySpeed
        : vEst < stationarySpeed;
    final nowStationary = slow && movedFromAnchor < anchorReleaseM;

    if (nowStationary) {
      // 1) Anker: laufender Mittelwert; Position einfrieren → kein Drift.
      if (!_stationary) {
        _anchorLat = lat;
        _anchorLon = lon;
        _anchorN = 1;
      } else {
        _anchorN++;
        _anchorLat = _anchorLat! + (lat - _anchorLat!) / _anchorN;
        _anchorLon = _anchorLon! + (lon - _anchorLon!) / _anchorN;
      }
      _stationary = true;
      _skips = 0;
      // KF am Anker halten, damit der Übergang zu Bewegung sauber ist.
      _kx.init((_anchorLon! - _lon0!) * _mPerDegLon, measVar);
      _ky.init((_anchorLat! - _lat0!) * _mPerDegLat, measVar);
      // Mitteln verbessert die Genauigkeit (∝ 1/√n), realistisch gedeckelt.
      final accOut = max(2.0, acc / sqrt(_anchorN.toDouble()));
      return (lat: _anchorLat!, lon: _anchorLon!, accuracy: accOut);
    }

    // 2)+3) Bewegung → 2D-CV-Kalman mit Innovations-Gating.
    _stationary = false;
    _anchorN = 0;
    final zx = (lon - _lon0!) * _mPerDegLon;
    final zy = (lat - _lat0!) * _mPerDegLat;

    _kx.predict(dt);
    _ky.predict(dt);

    // Innovation (Mahalanobis, 2 Freiheitsgrade) → Ausreißer erkennen.
    final ix = zx - _kx.p;
    final iy = zy - _ky.p;
    final sx = _kx.p00 + measVar;
    final sy = _ky.p00 + measVar;
    final maha = sqrt(ix * ix / sx + iy * iy / sy);

    if (maha > outlierGate && _skips < maxSkips) {
      // Ausreißer: Update überspringen, auf Prädiktion coasten (begrenzt).
      _skips++;
    } else {
      _skips = 0;
      _kx.update(zx, measVar);
      _ky.update(zy, measVar);
    }

    final outLon = _lon0! + _kx.p / _mPerDegLon;
    final outLat = _lat0! + _ky.p / _mPerDegLat;
    _anchorLat = outLat; // Basis für die nächste Stillstandsphase
    _anchorLon = outLon;
    final accOut = max(2.0, sqrt((_kx.p00 + _ky.p00) / 2.0));
    return (lat: outLat, lon: outLon, accuracy: accOut);
  }

  double _distM(double lat1, double lon1, double lat2, double lon2) {
    final dy = (lat1 - lat2) * _mPerDegLat;
    final dx = (lon1 - lon2) * _mPerDegLon;
    return sqrt(dx * dx + dy * dy);
  }
}

/// 2-Zustands-Kalman (Position, Geschwindigkeit) für eine Achse,
/// Constant-Velocity-Modell mit diskretem White-Noise-Acceleration-Q.
class _Kf1d {
  final double accelVar; // σa²
  double p = 0, v = 0; // Zustand
  double p00 = 0, p01 = 0, p10 = 0, p11 = 0; // Kovarianz
  bool _init = false;

  _Kf1d(this.accelVar);

  bool get isInit => _init;

  void reset() {
    p = 0;
    v = 0;
    p00 = p01 = p10 = p11 = 0;
    _init = false;
  }

  void init(double pos, double posVar) {
    p = pos;
    v = 0;
    p00 = posVar;
    p01 = 0;
    p10 = 0;
    // Anfangs sehr unsichere Geschwindigkeit: sonst würde der erste echte
    // Bewegungsschritt (Prädiktion aus v=0) fälschlich als Ausreißer verworfen.
    // Groß gewählt → der Filter lernt die Geschwindigkeit binnen 1–2 Fixes.
    p11 = 1000.0;
    _init = true;
  }

  void predict(double dt) {
    // Zustand: p += v·dt
    p = p + v * dt;
    // P = F·P·Fᵀ + Q,  F = [[1,dt],[0,1]]
    final a00 = p00 + dt * p10;
    final a01 = p01 + dt * p11;
    final a10 = p10;
    final a11 = p11;
    final n00 = a00 + a01 * dt;
    final n01 = a01;
    final n10 = a10 + a11 * dt;
    final n11 = a11;
    final dt2 = dt * dt, dt3 = dt2 * dt, dt4 = dt2 * dt2;
    p00 = n00 + accelVar * dt4 / 4.0;
    p01 = n01 + accelVar * dt3 / 2.0;
    p10 = n10 + accelVar * dt3 / 2.0;
    p11 = n11 + accelVar * dt2;
  }

  void update(double z, double measVar) {
    final s = p00 + measVar;
    final k0 = p00 / s;
    final k1 = p10 / s;
    final y = z - p;
    p = p + k0 * y;
    v = v + k1 * y;
    // P = (I - K·H)·P,  H = [1,0]
    final np00 = (1 - k0) * p00;
    final np01 = (1 - k0) * p01;
    final np10 = p10 - k1 * p00;
    final np11 = p11 - k1 * p01;
    p00 = np00;
    p01 = np01;
    p10 = np10;
    p11 = np11;
  }
}
