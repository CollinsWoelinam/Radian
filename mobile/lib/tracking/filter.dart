import 'fix.dart';

enum FilterDecision { accept, inaccurate, stationary, jump }

/// On-device noise filter: drops fixes that are too inaccurate to be useful,
/// GPS glitches that would need an impossible speed to reach, and
/// near-duplicates while parked, but still lets one through every
/// [keepAlive] so the dispatcher can tell a parked vehicle from a dead phone.
class LocationFilter {
  LocationFilter({
    this.distanceFilterM = 10,
    this.maxAccuracyM = 50,
    this.stationarySpeedKmh = 3.6,
    this.keepAlive = const Duration(seconds: 30),
    this.maxPlausibleKmh = 250,
    this.jumpConfirmations = 3,
  });

  double distanceFilterM;
  double maxAccuracyM;
  double stationarySpeedKmh;
  Duration keepAlive;

  /// Faster than any road vehicle; anything implying more is a glitch.
  final double maxPlausibleKmh;

  /// A jump this many fixes in a row, all agreeing with each other, is real
  /// (e.g. the phone was off while the vehicle moved) and is accepted.
  final int jumpConfirmations;

  Fix? _last;
  final List<Fix> _jumped = [];

  FilterDecision check(Fix f) {
    if (f.accuracyM != null && f.accuracyM! > maxAccuracyM) {
      return FilterDecision.inaccurate;
    }
    final last = _last;
    if (last == null) {
      _last = f;
      return FilterDecision.accept;
    }

    if (_implausible(last, f)) {
      if (_jumped.isNotEmpty && _implausible(_jumped.last, f)) _jumped.clear();
      _jumped.add(f);
      if (_jumped.length < jumpConfirmations) return FilterDecision.jump;
      // Consistently somewhere new: the vehicle really is there.
      _jumped.clear();
      _last = f;
      return FilterDecision.accept;
    }
    _jumped.clear();

    final moved = fixDistanceM(last, f);
    final slow = (f.speedKmh ?? 0) < stationarySpeedKmh;
    final stale = f.recordedAt.difference(last.recordedAt) >= keepAlive;
    if (moved < distanceFilterM && slow && !stale) {
      return FilterDecision.stationary;
    }
    _last = f;
    return FilterDecision.accept;
  }

  bool _implausible(Fix from, Fix to) {
    final d = fixDistanceM(from, to);
    if (d < 200) return false; // within normal GPS error, whatever the timing
    final secs = to.recordedAt.difference(from.recordedAt).inMilliseconds / 1000;
    if (secs <= 0) return true;
    return d / secs * 3.6 > maxPlausibleKmh;
  }
}
