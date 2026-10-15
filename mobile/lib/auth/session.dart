import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class Session {
  Session({
    required this.token,
    required this.expiresAt,
    required this.driverName,
    required this.vehicleId,
    required this.plate,
    required this.vehicleKind,
  });

  final String token;
  final DateTime expiresAt;
  final String driverName;
  final String vehicleId;
  final String plate;
  final String vehicleKind;

  bool get expired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'token': token,
        'expires_at': expiresAt.toIso8601String(),
        'driver_name': driverName,
        'vehicle_id': vehicleId,
        'plate': plate,
        'vehicle_kind': vehicleKind,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        driverName: j['driver_name'] as String,
        vehicleId: j['vehicle_id'] as String,
        plate: j['plate'] as String,
        vehicleKind: j['vehicle_kind'] as String,
      );
}

/// Persists the session in the platform keystore (Keychain / EncryptedSharedPreferences),
/// readable from the Android background service as well as the UI.
class SessionStore {
  static const _key = 'radian.session';
  static const _storage = FlutterSecureStorage();

  static Future<Session?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final s = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return s.expired ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Session s) => _storage.write(key: _key, value: jsonEncode(s.toJson()));

  static Future<void> clear() => _storage.delete(key: _key);

  /// Returns a token that is valid for at least [margin], refreshing and
  /// persisting a new one when the current one is close to expiry. Falls back
  /// to the current token if the server can't be reached.
  static Future<String?> freshToken({Duration margin = const Duration(days: 2)}) async {
    final s = await load();
    if (s == null) return null;
    if (s.expiresAt.difference(DateTime.now()) > margin) return s.token;
    try {
      final r = await AuthApi.refresh(s.token);
      await save(Session(
        token: r.token,
        expiresAt: r.expiresAt,
        driverName: s.driverName,
        vehicleId: s.vehicleId,
        plate: s.plate,
        vehicleKind: s.vehicleKind,
      ));
      return r.token;
    } catch (_) {
      return s.token;
    }
  }
}

/// Whether a shift is in progress, persisted so it survives the app or the
/// tracking service being killed: on next launch the shift resumes.
class ShiftStore {
  static const _key = 'radian.shift_started_at';
  static const _storage = FlutterSecureStorage();

  /// When the current shift started, or null if off shift.
  static Future<DateTime?> startedAt() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Marks the shift as started; keeps the original start time on resume.
  static Future<DateTime> begin() async {
    final existing = await startedAt();
    if (existing != null) return existing;
    final now = DateTime.now();
    await _storage.write(key: _key, value: now.toIso8601String());
    return now;
  }

  static Future<void> end() => _storage.delete(key: _key);
}

class LoginException implements Exception {
  LoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthApi {
  static Future<({String token, DateTime expiresAt})> refresh(String token) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.apiUrl}/v1/auth/device/refresh'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw LoginException('Token refresh failed (${res.statusCode}).');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (token: body['token'] as String, expiresAt: DateTime.parse(body['expires_at'] as String));
  }

  static Future<Session> login(String phone, String password) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AppConfig.apiUrl}/v1/auth/driver/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw LoginException("Can't reach the server. Check your connection and try again.");
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw LoginException(body['message'] as String? ?? 'Sign-in failed (${res.statusCode}).');
    }
    final driver = body['driver'] as Map<String, dynamic>;
    final vehicle = body['vehicle'] as Map<String, dynamic>;
    return Session(
      token: body['token'] as String,
      expiresAt: DateTime.parse(body['expires_at'] as String),
      driverName: driver['full_name'] as String,
      vehicleId: vehicle['id'] as String,
      plate: vehicle['license_plate'] as String,
      vehicleKind: vehicle['kind'] as String,
    );
  }
}
