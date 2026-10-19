import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';

import '../gen/radian/telemetry/v1/telemetry.pb.dart';

/// A GPS fix, independent of the location plugin so the tracking logic can be
/// unit-tested without a device.
class Fix {
  Fix({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.speedKmh,
    this.headingDeg,
    this.accuracyM,
    this.altitudeM,
  });

  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? speedKmh;
  final double? headingDeg;
  final double? accuracyM;
  final double? altitudeM;

  LocationPoint toPoint({required int seq, int? batteryPct}) {
    final p = LocationPoint(
      seq: Int64(seq),
      latitude: lat,
      longitude: lon,
      recordedAtMs: Int64(recordedAt.millisecondsSinceEpoch),
    );
    if (speedKmh != null) p.speedKmh = speedKmh!;
    if (headingDeg != null) p.headingDeg = headingDeg! % 360;
    if (accuracyM != null) p.accuracyM = accuracyM!;
    if (altitudeM != null) p.altitudeM = altitudeM!;
    if (batteryPct != null) p.batteryPct = batteryPct;
    return p;
  }
}

const _earthRadiusM = 6371008.8;

/// Haversine distance in meters.
double distanceM(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

double fixDistanceM(Fix a, Fix b) => distanceM(a.lat, a.lon, b.lat, b.lon);

/// Initial bearing from point 1 to point 2, degrees clockwise from north.
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final y = math.sin(rad(lon2 - lon1)) * math.cos(rad(lat2));
  final x = math.cos(rad(lat1)) * math.sin(rad(lat2)) -
      math.sin(rad(lat1)) * math.cos(rad(lat2)) * math.cos(rad(lon2 - lon1));
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Distance to add to a shift's total when moving from [prev] to [f].
///
/// GPS jitter on a parked phone produces a stream of small "moves" (indoors,
/// 25-30 m jumps while reporting ±11 m); counting them credits a stationary
/// driver with kilometres. When the fix carries a speed (real phones measure
/// it independently of position), only count steps taken while moving, plus
/// large jumps that catch up after a signal gap. Without a speed, require the
/// jump to exceed both fixes' error. Impossible jumps are never counted.
double drivenDistanceM(Fix? prev, Fix f, {double movingKmh = 5, double maxPlausibleKmh = 250, double catchUpM = 100}) {
  if (prev == null) return 0;
  final d = fixDistanceM(prev, f);
  final secs = f.recordedAt.difference(prev.recordedAt).inMilliseconds / 1000;
  if (secs <= 0 || d / secs * 3.6 > maxPlausibleKmh) return 0;
  final speed = f.speedKmh;
  if (speed != null) return speed >= movingKmh || d > catchUpM ? d : 0;
  return d > (prev.accuracyM ?? 10) + (f.accuracyM ?? 10) ? d : 0;
}
