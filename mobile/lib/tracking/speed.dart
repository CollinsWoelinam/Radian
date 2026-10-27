import 'fix.dart';

/// Picks a trustworthy speed (and heading) for each GPS fix.
///
/// Real phones report speed from the GNSS Doppler measurement, with an
/// accuracy estimate: that's the best source, even when it says 0. Some
/// sources (emulators, simulators, network fixes) report no usable speed; for
/// those we derive it from movement, but only when the movement clearly
/// exceeds the fixes' own error. Otherwise indoor jitter of 20-30 m between
/// two fixes a second apart reads as ~90 km/h for a parked phone.
class SpeedEstimator {
  SpeedEstimator({this.maxPlausibleKmh = 250});

  final double maxPlausibleKmh;

  /// Reference fix for deriving speed; advanced only after [_minGap] so
  /// high-rate sources still give a meaningful baseline.
  _Ref? _ref;
  static const _minGap = Duration(seconds: 2);
  static const _maxGap = Duration(seconds: 30);
  static const _maxRefAccuracyM = 25.0;
  // Coarse fixes (cell/Wi-Fi, hundreds of meters) can carry a speed too, but
  // it is noise: a phone on a desk read 28 km/h from a ±300 m fix.
  static const _maxSpeedAccuracyM = 100.0;

  ({double? speedKmh, double? headingDeg}) estimate({
    required double lat,
    required double lon,
    required DateTime at,
    required double accuracyM,
    required double speedMps,
    required double speedAccuracyMps,
    required double headingDeg,
  }) {
    final platformKmh = speedMps * 3.6;
    final plausible = speedMps >= 0 && platformKmh <= maxPlausibleKmh && accuracyM <= _maxSpeedAccuracyM;
    final platformHeading = headingDeg >= 0 && speedMps > 0.5 ? headingDeg : null;

    double? speed;
    double? heading;
    if (plausible && speedAccuracyMps > 0) {
      // Measured speed with an error estimate: trust it, including 0.
      speed = platformKmh;
      heading = platformHeading;
    } else if (plausible && speedMps > 0.5) {
      // Speed without an error estimate, but clearly moving.
      speed = platformKmh;
      heading = platformHeading;
    } else {
      final derived = _derive(lat, lon, at, accuracyM);
      speed = derived.speedKmh ?? (plausible ? platformKmh : null);
      heading = derived.headingDeg;
    }

    final ref = _ref;
    final accurate = accuracyM > 0 && accuracyM <= _maxRefAccuracyM;
    if (accurate && (ref == null || at.difference(ref.at) >= _minGap || at.isBefore(ref.at))) {
      _ref = _Ref(lat, lon, at, accuracyM);
    }
    return (speedKmh: speed, headingDeg: heading);
  }

  ({double? speedKmh, double? headingDeg}) _derive(double lat, double lon, DateTime at, double accuracyM) {
    final ref = _ref;
    if (ref == null || accuracyM <= 0 || accuracyM > _maxRefAccuracyM) return (speedKmh: null, headingDeg: null);
    final gap = at.difference(ref.at);
    if (gap < _minGap || gap > _maxGap) return (speedKmh: null, headingDeg: null);
    final d = distanceM(ref.lat, ref.lon, lat, lon);
    // Within the combined error of the two fixes: indistinguishable from standing still.
    if (d <= ref.accuracyM + accuracyM) return (speedKmh: 0, headingDeg: null);
    final kmh = d / (gap.inMilliseconds / 1000) * 3.6;
    if (kmh > maxPlausibleKmh) return (speedKmh: null, headingDeg: null);
    return (speedKmh: kmh, headingDeg: bearingDeg(ref.lat, ref.lon, lat, lon));
  }
}

class _Ref {
  _Ref(this.lat, this.lon, this.at, this.accuracyM);
  final double lat, lon, accuracyM;
  final DateTime at;
}
