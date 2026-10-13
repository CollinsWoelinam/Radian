import 'package:fixnum/fixnum.dart';
import 'package:sqflite/sqflite.dart';

import '../gen/radian/telemetry/v1/telemetry.pb.dart';

/// Durable outbox for GPS points. Every accepted fix is written here first
/// and deleted only once the server acks it, so dead zones, crashes and
/// reboots lose nothing. Capped as a ring buffer: past [capacity] points
/// (~27 h at a 2 s interval) the oldest are dropped.
class PointBuffer {
  PointBuffer._(this._db, this.capacity);

  final Database _db;
  final int capacity;
  int _nextSeq = 1;

  static Future<PointBuffer> open({
    String? path,
    DatabaseFactory? factory,
    int capacity = 50000,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? '${await f.getDatabasesPath()}/radian_outbox.db';
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE points (seq INTEGER PRIMARY KEY, recorded_at INTEGER NOT NULL, data BLOB NOT NULL)');
          await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL)');
        },
      ),
    );
    final buf = PointBuffer._(db, capacity);
    final rows = await db.query('meta', where: 'key = ?', whereArgs: ['next_seq']);
    if (rows.isNotEmpty) buf._nextSeq = rows.first['value'] as int;
    return buf;
  }

  /// Assigns the next sequence number, stores the point, and returns it.
  Future<LocationPoint> add(LocationPoint p) async {
    final seq = _nextSeq++;
    p.seq = Int64(seq);
    await _db.transaction((tx) async {
      await tx.insert('points', {
        'seq': seq,
        'recorded_at': p.recordedAtMs.toInt(),
        'data': p.writeToBuffer(),
      });
      await tx.insert('meta', {'key': 'next_seq', 'value': _nextSeq},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.rawDelete(
        'DELETE FROM points WHERE seq <= (SELECT MAX(seq) FROM points) - ?',
        [capacity],
      );
    });
    return p;
  }

  /// Points with seq > [afterSeq], oldest first.
  Future<List<LocationPoint>> after(int afterSeq, {int limit = 500}) async {
    final rows = await _db.query('points',
        columns: ['data'], where: 'seq > ?', whereArgs: [afterSeq], orderBy: 'seq', limit: limit);
    return [for (final r in rows) LocationPoint.fromBuffer(r['data'] as List<int>)];
  }

  /// Drops everything the server has acknowledged.
  Future<int> ack(int seq) => _db.delete('points', where: 'seq <= ?', whereArgs: [seq]);

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM points')) ?? 0;

  Future<void> close() => _db.close();
}
