import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radian_driver/gen/radian/telemetry/v1/telemetry.pb.dart';
import 'package:radian_driver/tracking/filter.dart';
import 'package:radian_driver/tracking/fix.dart';
import 'package:radian_driver/tracking/motion.dart';
import 'package:radian_driver/tracking/point_buffer.dart';
import 'package:radian_driver/tracking/speed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final t0 = DateTime.utc(2026, 10, 13, 9);

/// Accra Central; ~111 m per 0.001° of latitude.
Fix at(int seconds, {double dLat = 0, double? kmh, double? acc}) =>
    Fix(lat: 5.55 + dLat, lon: -0.2, recordedAt: t0.add(Duration(seconds: seconds)), speedKmh: kmh, accuracyM: acc);

void main() {
  group('LocationFilter', () {
    test('drops inaccurate fixes', () {
      expect(LocationFilter().check(at(0, acc: 120)), FilterDecision.inaccurate);
    });

    test('drops parked jitter but keeps one fix per keep-alive window', () {
      final f = LocationFilter();
      expect(f.check(at(0, kmh: 0)), FilterDecision.accept);
      expect(f.check(at(2, dLat: 0.00003, kmh: 0.5)), FilterDecision.stationary); // ~3 m wobble
      expect(f.check(at(31, dLat: 0.00002, kmh: 0)), FilterDecision.accept); // keep-alive
    });

    test('accepts small moves at speed', () {
      final f = LocationFilter();
      f.check(at(0, kmh: 30));
      expect(f.check(at(1, dLat: 0.00005, kmh: 30)), FilterDecision.accept);
    });
  });

  group('LocationFilter jumps', () {
    // ~0.11° latitude ≈ 12 km; 37.7858,-122.4064 is the simulator default (SF).
    Fix far(int seconds, {double dLat = 0}) =>
        Fix(lat: 37.7858 + dLat, lon: -122.4064, recordedAt: t0.add(Duration(seconds: seconds)), accuracyM: 5);

    test('rejects a one-off teleport and keeps tracking from the real spot', () {
      final f = LocationFilter();
      expect(f.check(at(0, kmh: 45)), FilterDecision.accept);
      expect(f.check(far(1)), FilterDecision.jump);
      expect(f.check(at(2, dLat: 0.0003, kmh: 45)), FilterDecision.accept);
    });

    test('accepts a new location once it is confirmed by consistent fixes', () {
      final f = LocationFilter();
      f.check(at(0, kmh: 45));
      expect(f.check(far(60)), FilterDecision.jump);
      expect(f.check(far(61, dLat: 0.0001)), FilterDecision.jump);
      expect(f.check(far(62, dLat: 0.0002)), FilterDecision.accept);
      expect(f.check(far(63, dLat: 0.0004)), FilterDecision.accept);
    });

    test('scattered glitches never confirm each other', () {
      final f = LocationFilter();
      f.check(at(0, kmh: 45));
      expect(f.check(far(1)), FilterDecision.jump);
      expect(f.check(at(2, dLat: 1.5)), FilterDecision.jump); // somewhere else again
      expect(f.check(far(3)), FilterDecision.jump);
    });

    test('a genuine fast highway segment is not a jump', () {
      final f = LocationFilter();
      f.check(at(0, kmh: 120));
      // 0.003° ≈ 333 m in 10 s = 120 km/h
      expect(f.check(at(10, dLat: 0.003, kmh: 120)), FilterDecision.accept);
    });
  });

  group('SpeedEstimator', () {
    // 0.0001° latitude ≈ 11 m
    ({double? speedKmh, double? headingDeg}) feed(SpeedEstimator e, int ms, double dLat,
            {double acc = 10, double speed = 0, double speedAcc = 0, double heading = -1}) =>
        e.estimate(
          lat: 5.55 + dLat,
          lon: -0.2,
          at: t0.add(Duration(milliseconds: ms)),
          accuracyM: acc,
          speedMps: speed,
          speedAccuracyMps: speedAcc,
          headingDeg: heading,
        );

    test('indoor jitter on a parked phone stays near zero', () {
      final e = SpeedEstimator();
      feed(e, 0, 0, acc: 12);
      // 25 m jumps every second, within the two fixes' combined error.
      for (var i = 1; i <= 6; i++) {
        final r = feed(e, i * 1000, (i.isOdd ? 0.00022 : 0), acc: 12);
        expect(r.speedKmh ?? 0, lessThan(5), reason: 'fix $i');
      }
    });

    test('ignores the speed on a coarse network fix', () {
      final e = SpeedEstimator();
      // A ±300 m cell/Wi-Fi fix claiming 28 km/h on a phone lying still.
      final r = feed(e, 0, 0, acc: 300, speed: 7.8, speedAcc: 1.5);
      expect(r.speedKmh, isNull);
    });

    test("trusts the phone's measured speed, including zero", () {
      final e = SpeedEstimator();
      feed(e, 0, 0);
      expect(feed(e, 3000, 0.0005, speed: 0, speedAcc: 0.3).speedKmh, 0);
      final moving = feed(e, 4000, 0.0006, speed: 12.5, speedAcc: 0.4, heading: 90);
      expect(moving.speedKmh, closeTo(45, 0.1));
      expect(moving.headingDeg, 90);
    });

    test('derives speed when the source reports none (emulator feed)', () {
      final e = SpeedEstimator();
      feed(e, 0, 0, acc: 5);
      // 25 m north every 2 s = 45 km/h, well beyond 10 m combined error.
      final r = feed(e, 2000, 0.000225, acc: 5);
      expect(r.speedKmh, closeTo(45, 2));
      expect(r.headingDeg, closeTo(0, 1));
    });
  });

  group('drivenDistanceM', () {
    test('parked jitter adds nothing; real driving adds the distance', () {
      final parked = at(0, kmh: 1, acc: 12);
      expect(drivenDistanceM(parked, at(1, dLat: 0.0002, kmh: 2, acc: 12)), 0); // 22 m jitter
      // Indoors: a 30 m jump while reporting ±11 m and measured speed 0.
      expect(drivenDistanceM(at(0, kmh: 0, acc: 11), at(1, dLat: 0.00027, kmh: 0, acc: 11)), 0);
      // No speed available (some providers): needs to beat the combined error.
      expect(drivenDistanceM(at(0, acc: 5), at(3, dLat: 0.0003, acc: 5)), closeTo(33, 1));
      final driving = drivenDistanceM(at(0, kmh: 40, acc: 8), at(2, dLat: 0.0002, kmh: 40, acc: 8));
      expect(driving, closeTo(22, 1));
    });

    test('a confirmed relocation is not counted as driven', () {
      final far = Fix(lat: 37.7858, lon: -122.4064, recordedAt: t0.add(const Duration(seconds: 60)), accuracyM: 5);
      expect(drivenDistanceM(at(0, kmh: 40), far), 0);
    });
  });

  group('MotionDetector', () {
    test('parks after two slow minutes in one spot, wakes on speed', () {
      final m = MotionDetector();
      expect(m.update(at(0, kmh: 1)), isFalse);
      expect(m.update(at(60, kmh: 0)), isFalse);
      expect(m.update(at(121, kmh: 0)), isTrue);
      expect(m.mode, MotionMode.parked);
      expect(m.update(at(150, kmh: 25, acc: 8)), isTrue);
      expect(m.mode, MotionMode.moving);
    });

    test('slow crawl in traffic never counts as parked', () {
      final m = MotionDetector();
      for (var i = 0; i <= 300; i += 10) {
        m.update(at(i, dLat: i * 0.0001, kmh: 3)); // ~11 m every 10 s
      }
      expect(m.mode, MotionMode.moving);
    });

    test('inaccurate low-power fix does not fake a departure', () {
      final m = MotionDetector()..update(at(0, kmh: 0));
      m.update(at(130, kmh: 0));
      expect(m.mode, MotionMode.parked);
      expect(m.update(at(160, dLat: 0.002, kmh: 0, acc: 150)), isFalse);
      expect(m.update(at(190, dLat: 0.002, kmh: 0, acc: 10)), isTrue); // real 220 m move
    });
  });

  group('PointBuffer', () {
    setUpAll(sqfliteFfiInit);

    LocationPoint p(int ms) => LocationPoint(latitude: 5.55, longitude: -0.2, recordedAtMs: Int64(ms));

    test('assigns increasing seqs, survives reopen, and acks', () async {
      final path = inMemoryDatabasePath;
      final buf = await PointBuffer.open(path: path, factory: databaseFactoryFfi);
      for (var i = 0; i < 5; i++) {
        await buf.add(p(i));
      }
      expect((await buf.after(0)).map((x) => x.seq.toInt()), [1, 2, 3, 4, 5]);
      expect((await buf.after(3)).map((x) => x.seq.toInt()), [4, 5]);
      expect(await buf.ack(3), 3);
      expect(await buf.count(), 2);
      await buf.close();
    });

    test('ring capacity drops the oldest points', () async {
      final buf = await PointBuffer.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi, capacity: 3);
      for (var i = 0; i < 5; i++) {
        await buf.add(p(i));
      }
      expect((await buf.after(0)).map((x) => x.seq.toInt()), [3, 4, 5]);
      await buf.close();
    });

    test('seq keeps increasing across restarts', () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/radian_test_${DateTime.now().microsecondsSinceEpoch}.db';
      var buf = await PointBuffer.open(path: path, factory: databaseFactoryFfi);
      await buf.add(p(1));
      await buf.add(p(2));
      await buf.ack(2);
      await buf.close();
      buf = await PointBuffer.open(path: path, factory: databaseFactoryFfi);
      expect((await buf.add(p(3))).seq.toInt(), 3);
      await buf.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });
}
