import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radian_driver/gen/radian/telemetry/v1/telemetry.pb.dart';
import 'package:radian_driver/tracking/filter.dart';
import 'package:radian_driver/tracking/fix.dart';
import 'package:radian_driver/tracking/motion.dart';
import 'package:radian_driver/tracking/point_buffer.dart';
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
