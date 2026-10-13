import 'fix.dart';

enum FilterDecision { accept, inaccurate, stationary }

/// On-device noise filter: drops fixes that are too inaccurate to be useful
/// and near-duplicates while parked, but still lets one through every
/// [keepAlive] so the dispatcher can tell a parked vehicle from a dead phone.
class LocationFilter {
  LocationFilter({
    this.distanceFilterM = 10,
    this.maxAccuracyM = 50,
    this.stationarySpeedKmh = 3.6,
    this.keepAlive = const Duration(seconds: 30),
  });

  double distanceFilterM;
  double maxAccuracyM;
  double stationarySpeedKmh;
  Duration keepAlive;

  Fix? _last;

  FilterDecision check(Fix f) {
    if (f.accuracyM != null && f.accuracyM! > maxAccuracyM) {
      return FilterDecision.inaccurate;
    }
    final last = _last;
    if (last != null) {
      final moved = fixDistanceM(last, f);
      final slow = (f.speedKmh ?? 0) < stationarySpeedKmh;
      final stale = f.recordedAt.difference(last.recordedAt) >= keepAlive;
      if (moved < distanceFilterM && slow && !stale) {
        return FilterDecision.stationary;
      }
    }
    _last = f;
    return FilterDecision.accept;
  }
}
