import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/session.dart';
import '../config.dart';

class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;

  static LatLon? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    return LatLon((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());
  }
}

/// The job offered to, or being worked by, this driver.
class DriverJob {
  DriverJob({
    required this.id,
    required this.number,
    required this.status,
    required this.priority,
    required this.pickup,
    required this.pickupAddress,
    this.dropoff,
    this.dropoffAddress,
    this.notes,
    this.etaSeconds,
    this.offerExpiresAt,
  });

  final String id;
  final int number;
  final String status;
  final int priority;
  final LatLon pickup;
  final String pickupAddress;
  final LatLon? dropoff;
  final String? dropoffAddress;
  final String? notes;
  final int? etaSeconds;
  final DateTime? offerExpiresAt;

  bool get isOffer => status == 'OFFERED';
  bool get urgent => priority <= 2;

  /// Where the driver is heading now.
  LatLon get destination => (status == 'ON_SITE' || status == 'EN_ROUTE_DROPOFF') && dropoff != null ? dropoff! : pickup;

  factory DriverJob.fromJson(Map<String, dynamic> j) => DriverJob(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        status: j['status'] as String,
        priority: (j['priority'] as num).toInt(),
        pickup: LatLon.fromJson(j['pickup'])!,
        pickupAddress: (j['pickup_address'] as String?) ?? '',
        dropoff: LatLon.fromJson(j['dropoff']),
        dropoffAddress: j['dropoff_address'] as String?,
        notes: j['notes'] as String?,
        etaSeconds: (j['eta_seconds'] as num?)?.toInt(),
        offerExpiresAt: j['offer_expires_at'] == null ? null : DateTime.parse(j['offer_expires_at'] as String),
      );
}

class JobActionException implements Exception {
  JobActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Driver-side job calls, authenticated with the device token.
class DriverJobApi {
  static Future<Map<String, String>> _headers() async {
    final token = await SessionStore.freshToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// The current offer or active job, or null if there is none.
  static Future<DriverJob?> current() async {
    final res = await http
        .get(Uri.parse('${AppConfig.apiUrl}/v1/driver/job'), headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 204) return null;
    if (res.statusCode != 200) throw JobActionException('Couldn\'t load your job (${res.statusCode}).');
    return DriverJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> accept(String id) => _post('/v1/driver/jobs/$id/accept');
  static Future<void> decline(String id) => _post('/v1/driver/jobs/$id/decline');
  static Future<void> setStatus(String id, String status) =>
      _post('/v1/driver/jobs/$id/status', body: {'status': status});

  static Future<void> _post(String path, {Map<String, String>? body}) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('${AppConfig.apiUrl}$path'), headers: await _headers(), body: body == null ? null : jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw JobActionException('No connection. Try again when you have signal.');
    }
    if (res.statusCode >= 300) {
      String msg = 'Something went wrong (${res.statusCode}).';
      try {
        msg = (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String? ?? msg;
      } catch (_) {}
      throw JobActionException(msg);
    }
  }
}
