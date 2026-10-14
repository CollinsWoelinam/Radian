import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../gen/radian/telemetry/v1/telemetry.pb.dart';
import 'filter.dart';
import 'fix.dart';
import 'motion.dart';
import 'point_buffer.dart';
import 'status.dart';
import 'uplink.dart';

/// The tracking pipeline: GPS -> motion detection -> noise filter -> durable
/// outbox -> WebSocket. Runs inside the Android foreground service, or in the
/// app process on iOS (kept alive by background location updates).
class TrackingEngine {
  TrackingEngine({required this.token, required this.ingestUrl, required this.buffer});

  final String token;
  final String ingestUrl;
  final PointBuffer buffer;

  final _status = StreamController<TrackerStatus>.broadcast();
  Stream<TrackerStatus> get status => _status.stream;
  TrackerStatus current = const TrackerStatus();

  final _filter = LocationFilter();
  final _motion = MotionDetector();
  final _battery = Battery();
  late final Uplink _uplink;

  StreamSubscription<Position>? _positions;
  Timer? _keepAlive;
  int _movingIntervalMs = 2000;
  int? _batteryPct;
  // Highest seq written on the current connection; reset on reconnect so
  // everything unacked is resent (the server de-duplicates).
  int _wroteSeq = 0;
  bool _flushing = false;

  Future<void> start() async {
    _uplink = Uplink(
      url: ingestUrl,
      token: token,
      onMessage: _onServerMessage,
      onState: (s) {
        _log('link: ${s.name}');
        if (s == LinkState.online) {
          _wroteSeq = 0;
          _flush();
        }
        _emit(current.copyWith(link: s));
      },
      onAuthRejected: () => _fail('Your session has expired. Sign in again.', authExpired: true),
    );
    _emit(current.copyWith(running: true, queued: await buffer.count()));
    _log('start: ingest=$ingestUrl queued=${current.queued}');
    _uplink.start();
    _listen();
    _refreshBattery();
  }

  Future<void> stop() async {
    _keepAlive?.cancel();
    await _positions?.cancel();
    await _uplink.stop();
    _emit(current.copyWith(running: false, link: LinkState.offline));
  }

  Future<void> _fail(String message, {bool authExpired = false}) async {
    await stop();
    _emit(TrackerStatus(error: message, authExpired: authExpired, queued: current.queued));
  }

  // --- Location -------------------------------------------------------------

  void _listen() {
    _positions?.cancel();
    _keepAlive?.cancel();
    final parked = _motion.mode == MotionMode.parked;
    _log('gps: ${parked ? 'low-power (parked)' : 'high precision'}');
    _positions = Geolocator.getPositionStream(locationSettings: _settings(parked)).listen(
      (p) => _onFix(_toFix(p)),
      onError: (Object e) async {
        _log('location stream error: $e');
        if (e is LocationServiceDisabledException && await _fallBackToLocationManager()) return;
        if (e is PermissionDeniedException || e is LocationServiceDisabledException) {
          _fail('Location is off or not permitted. Turn it on to stay on shift.');
        } else {
          // Surface anything unexpected instead of silently tracking nothing.
          _emit(current.copyWith(error: 'GPS error: $e'));
        }
      },
    );
    if (parked) {
      // The low-power stream may stay silent while parked; take an accurate
      // fix every minute so the dispatcher still sees a live vehicle and we
      // notice when it pulls away.
      _keepAlive = Timer.periodic(const Duration(minutes: 1), (_) async {
        try {
          final p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
          );
          _onFix(_toFix(p));
        } catch (_) {}
      });
    }
  }

  bool _useLocationManager = false;

  /// Play Services' fused provider reports "location disabled" when its own
  /// settings check fails (e.g. Google Location Accuracy off). In the
  /// foreground it would show a fix-it dialog; a background service can't, so
  /// fall back to the platform GPS provider if location is actually on.
  Future<bool> _fallBackToLocationManager() async {
    if (!Platform.isAndroid || _useLocationManager) return false;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    _useLocationManager = true;
    _log('fused provider unavailable; falling back to LocationManager');
    _listen();
    return true;
  }

  LocationSettings _settings(bool parked) {
    final accuracy = parked ? LocationAccuracy.medium : LocationAccuracy.bestForNavigation;
    final distance = parked ? 50 : 5;
    if (Platform.isAndroid) {
      return AndroidSettings(
        forceLocationManager: _useLocationManager,
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: Duration(milliseconds: parked ? 30000 : _movingIntervalMs),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distance);
  }

  // Reference fix for deriving speed; replaced only once >= 1 s has passed so
  // high-rate sources (fixes every few hundred ms) still yield a speed.
  Fix? _speedRef;

  Fix _toFix(Position p) {
    // Trust the platform's speed only above walking pace: some providers
    // (emulator GPS, network fixes) report ~0 even while moving.
    var speedKmh = p.speed > 0.5 ? p.speed * 3.6 : null;
    double? heading = p.heading >= 0 && p.speed > 0.5 ? p.heading : null;
    final accurate = p.accuracy > 0 && p.accuracy <= 25;
    final ref = _speedRef;
    final dt = ref == null ? 0.0 : p.timestamp.difference(ref.recordedAt).inMilliseconds / 1000;

    // Otherwise derive it from the reference fix when both are accurate.
    if (speedKmh == null && ref != null && accurate && dt >= 1 && dt <= 30) {
      final d = distanceM(ref.lat, ref.lon, p.latitude, p.longitude);
      speedKmh = d / dt * 3.6;
      if (d > 5) heading = bearingDeg(ref.lat, ref.lon, p.latitude, p.longitude);
    }

    final f = Fix(
      lat: p.latitude,
      lon: p.longitude,
      recordedAt: p.timestamp,
      speedKmh: speedKmh ?? (p.speed >= 0 ? p.speed * 3.6 : null),
      headingDeg: heading,
      accuracyM: p.accuracy > 0 ? p.accuracy : null,
      altitudeM: p.altitude != 0 ? p.altitude : null,
    );
    if (accurate && (ref == null || dt >= 1 || dt < 0)) _speedRef = f;
    return f;
  }

  int _fixes = 0;

  Future<void> _onFix(Fix f) async {
    if (_fixes++ % 30 == 0) _log('fix #$_fixes acc=${f.accuracyM?.round()}m speed=${f.speedKmh?.round()}km/h');
    if (_motion.update(f)) _listen(); // switch between precise and low-power GPS

    _emit(current.copyWith(
      lat: f.lat,
      lon: f.lon,
      speedKmh: f.speedKmh,
      accuracyM: f.accuracyM,
      lastFixAt: f.recordedAt,
      mode: _motion.mode,
    ));

    if (_filter.check(f) != FilterDecision.accept) return;
    await buffer.add(f.toPoint(seq: 0, batteryPct: _batteryPct));
    _emit(current.copyWith(queued: current.queued + 1));
    _flush();
  }

  // --- Upload ---------------------------------------------------------------

  Future<void> _flush() async {
    if (_flushing || !_uplink.isOpen) return;
    _flushing = true;
    try {
      while (_uplink.isOpen) {
        final points = await buffer.after(_wroteSeq, limit: 500);
        if (points.isEmpty) break;
        final oldest = DateTime.fromMillisecondsSinceEpoch(points.first.recordedAtMs.toInt());
        final backfill = DateTime.now().difference(oldest) > const Duration(seconds: 30);
        final ok = _uplink.send(ClientMessage(batch: TelemetryBatch(points: points, isBackfill: backfill)));
        if (!ok) break;
        _wroteSeq = points.last.seq.toInt();
        _emit(current.copyWith(sent: current.sent + points.length));
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _onServerMessage(ServerMessage msg) async {
    switch (msg.whichPayload()) {
      case ServerMessage_Payload.ack:
        final seq = msg.ack.ackedSeq.toInt();
        final removed = await buffer.ack(seq);
        _emit(current.copyWith(acked: current.acked + removed, queued: await buffer.count()));
        _refreshBattery();
      case ServerMessage_Payload.config:
        final c = msg.config;
        if (c.distanceFilterM > 0) _filter.distanceFilterM = c.distanceFilterM.toDouble();
        if (c.maxAccuracyM > 0) _filter.maxAccuracyM = c.maxAccuracyM;
        if (c.stationarySpeedKmh > 0) _motion.movingKmh = c.stationarySpeedKmh;
        if (c.movingIntervalMs > 0 && c.movingIntervalMs != _movingIntervalMs) {
          _movingIntervalMs = c.movingIntervalMs;
          if (_motion.mode == MotionMode.moving) _listen();
        }
      case ServerMessage_Payload.jobOffer:
      case ServerMessage_Payload.notSet:
        break; // dispatch lands in the next step
    }
  }

  Future<void> _refreshBattery() async {
    try {
      final level = await _battery.batteryLevel;
      // Simulators and some devices report -1 when unknown.
      _batteryPct = level >= 0 && level <= 100 ? level : null;
    } catch (_) {}
  }

  void _emit(TrackerStatus s) {
    current = s;
    if (!_status.isClosed) _status.add(s);
  }
}

void _log(String msg) => debugPrint('[radian.tracker] $msg');
