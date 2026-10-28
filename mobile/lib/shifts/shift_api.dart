import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/session.dart';
import '../config.dart';
import '../jobs/driver_job.dart';

/// A shift as the server records it; totals are filled in when it ends.
class ShiftSummary {
  const ShiftSummary({required this.id, required this.startedAt, this.endedAt, this.distanceM, this.drivingS, this.jobsCompleted});
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? distanceM;
  final int? drivingS;
  final int? jobsCompleted;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  static ShiftSummary fromJson(Map<String, dynamic> j) => ShiftSummary(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
        endedAt: j['ended_at'] == null ? null : DateTime.parse(j['ended_at'] as String).toLocal(),
        distanceM: (j['distance_m'] as num?)?.toDouble(),
        drivingS: (j['driving_s'] as num?)?.toInt(),
        jobsCompleted: (j['jobs_completed'] as num?)?.toInt(),
      );
}

class ShiftJob {
  const ShiftJob({required this.number, required this.pickupAddress, required this.dropoffAddress, required this.completedAt});
  final int number;
  final String pickupAddress;
  final String dropoffAddress;
  final DateTime completedAt;
}

/// One shift with its route and the jobs completed during it.
class ShiftDetail {
  const ShiftDetail({required this.shift, required this.distanceM, required this.drivingS, required this.topSpeedKmh, required this.route, required this.jobs});
  final ShiftSummary shift;
  final double distanceM;
  final int drivingS;
  final double topSpeedKmh;
  final List<LatLon> route;
  final List<ShiftJob> jobs;

  static ShiftDetail fromJson(Map<String, dynamic> j) {
    final summary = j['summary'] as Map<String, dynamic>;
    return ShiftDetail(
      shift: ShiftSummary.fromJson(j),
      distanceM: (summary['distance_m'] as num).toDouble(),
      drivingS: (summary['driving_s'] as num).toInt(),
      topSpeedKmh: (summary['top_speed_kmh'] as num).toDouble(),
      // [unix ms, lat, lon, speed]
      route: [for (final p in j['points'] as List) LatLon((p[1] as num).toDouble(), (p[2] as num).toDouble())],
      jobs: [
        for (final x in j['jobs'] as List)
          ShiftJob(
            number: (x['number'] as num).toInt(),
            pickupAddress: x['pickup_address'] as String? ?? '',
            dropoffAddress: x['dropoff_address'] as String? ?? '',
            completedAt: DateTime.parse(x['completed_at'] as String).toLocal(),
          ),
      ],
    );
  }
}

class ShiftApiException implements Exception {
  ShiftApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Shift records on the server, authenticated with the device token.
class ShiftApi {
  static Future<Map<String, String>> _headers() async {
    final token = await SessionStore.freshToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Future<dynamic> _call(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('${AppConfig.apiUrl}$path');
    final headers = await _headers();
    final http.Response res;
    try {
      res = await (method == 'GET' ? http.get(uri, headers: headers) : http.post(uri, headers: headers, body: jsonEncode(body ?? {})))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ShiftApiException('No connection.');
    }
    if (res.statusCode >= 300) throw ShiftApiException('Request failed (${res.statusCode}).');
    return jsonDecode(res.body);
  }

  /// Opens a shift on the server (idempotent).
  static Future<ShiftSummary> start(DateTime startedAt) async =>
      ShiftSummary.fromJson(await _call('POST', '/v1/driver/shifts/start', {'started_at': startedAt.toUtc().toIso8601String()}) as Map<String, dynamic>);

  /// Closes the shift and returns its summary. started_at covers a start that never reached the server.
  static Future<ShiftDetail> end(DateTime startedAt, DateTime endedAt) async => ShiftDetail.fromJson(await _call('POST', '/v1/driver/shifts/end', {
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
      }) as Map<String, dynamic>);

  static Future<List<ShiftSummary>> list({int limit = 30}) async =>
      [for (final s in await _call('GET', '/v1/driver/shifts?limit=$limit') as List) ShiftSummary.fromJson(s as Map<String, dynamic>)];

  static Future<ShiftDetail> get(String id) async => ShiftDetail.fromJson(await _call('GET', '/v1/driver/shifts/$id') as Map<String, dynamic>);
}
