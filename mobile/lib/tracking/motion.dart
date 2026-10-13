import 'fix.dart';

enum MotionMode { moving, parked }

/// Decides when to drop GPS into low-power mode. A vehicle counts as parked
/// after staying slow and within [wakeRadiusM] of one spot for
/// [parkedAfter]; it wakes as soon as it is fast again or leaves that spot.
class MotionDetector {
  MotionDetector({
    this.movingKmh = 5,
    this.parkedAfter = const Duration(minutes: 2),
    this.wakeRadiusM = 60,
    this.maxWakeAccuracyM = 40,
  });

  double movingKmh;
  final Duration parkedAfter;
  final double wakeRadiusM;
  // Low-power fixes can be off by 100 m+; don't let them fake a departure.
  final double maxWakeAccuracyM;

  MotionMode mode = MotionMode.moving;
  Fix? _anchor;

  /// Feeds a fix; returns true when the mode changed.
  bool update(Fix f) {
    final fast = (f.speedKmh ?? 0) >= movingKmh;
    final accurate = (f.accuracyM ?? 0) <= maxWakeAccuracyM;

    switch (mode) {
      case MotionMode.moving:
        if (fast) {
          _anchor = null;
          return false;
        }
        final anchor = _anchor ??= f;
        if (fixDistanceM(anchor, f) > wakeRadiusM) {
          _anchor = f; // drifting slowly (traffic): restart the clock here
          return false;
        }
        if (f.recordedAt.difference(anchor.recordedAt) >= parkedAfter) {
          mode = MotionMode.parked;
          return true;
        }
        return false;

      case MotionMode.parked:
        final left = accurate && _anchor != null && fixDistanceM(_anchor!, f) > wakeRadiusM;
        if ((fast && accurate) || left) {
          mode = MotionMode.moving;
          _anchor = null;
          return true;
        }
        return false;
    }
  }
}
