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
import 'speed.dart';
import 'status.dart';
import 'uplink.dart';

/// The tracking pipeline: GPS -> motion detection -> noise filter -> durable
/// outbox -> WebSocket. Runs inside the Android foreground service, or in the
/// app process on iOS (kept alive by background location updates).
class TrackingEngine {
  TrackingEngine({
    required this.token,
    required this.ingestUrl,
    required this.buffer,
    this.startedAt,
    this.refreshToken,
    this.onJobOffer,
  });

  final String token;
  final String ingestUrl;
  final PointBuffer buffer;
  final DateTime? startedAt;

  /// Returns a token valid for a while yet (refreshing it if needed), so a
  /// long-running shift never hits token expiry.
  final Future<String?> Function()? refreshToken;

  /// Called when dispatch pushes a job offer (e.g. to post a notification).
  final void Function(JobOffer offer)? onJobOffer;

  /// Platform speeds above this are glitches; fall back to deriving speed.
  static const _maxPlausibleKmh = 250.0;

  final _status = StreamController<TrackerStatus>.broadcast();
  Stream<TrackerStatus> get status => _status.stream;
  TrackerStatus current = const TrackerStatus();

  final _filter = LocationFilter();
  final _motion = MotionDetector();
  final _battery = Battery();
  late final Uplink _uplink;

  StreamSubscription<Position>? _positions;
  Timer? _keepAlive;
  Timer? _tokenTimer;
  Fix? _lastAccepted;
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
    _emit(current.copyWith(running: true, queued: await buffer.count(), startedAt: startedAt ?? DateTime.now()));
    _log('start: ingest=$ingestUrl queued=${current.queued}');
    _uplink.start();
    _listen();
    _refreshBattery();
    _renewToken();
    _tokenTimer = Timer.periodic(const Duration(hours: 1), (_) => _renewToken());
  }

  Future<void> stop() async {
    _log('stop: requested');
    _keepAlive?.cancel();
    _tokenTimer?.cancel();
    await _positions?.cancel();
    await _uplink.stop();
    _emit(current.copyWith(running: false, link: LinkState.offline));
    _log('stop: done (queued=${current.queued})');
  }

  Future<void> _renewToken() async {
    final fresh = await refreshToken?.call();
    if (fresh != null && fresh != _uplink.token) {
      _uplink.token = fresh;
      _log('device token refreshed');
    }
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
    _startWatchdog();
  }

  DateTime? _lastFixReceivedAt;
  bool _watchdogBusy = false;

  /// Requests a fix whenever the stream has gone quiet. A still phone may get
  /// no stream updates at all (parked low-power mode, or an OS that holds
  /// updates while nothing changes); without this the dispatcher would see a
  /// live, on-shift vehicle drop off the map as "offline".
  void _startWatchdog() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) async {
      final quiet = _motion.mode == MotionMode.parked ? const Duration(seconds: 60) : const Duration(seconds: 30);
      final last = _lastFixReceivedAt;
      if (_watchdogBusy || (last != null && DateTime.now().difference(last) < quiet)) return;
      _watchdogBusy = true;
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 20),
          ),
        );
        _log('watchdog fix after ${last == null ? '-' : DateTime.now().difference(last).inSeconds}s of silence');
        _onFix(_toFix(p));
      } catch (e) {
        _log('watchdog fix failed: $e');
      } finally {
        _watchdogBusy = false;
      }
    });
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
    // No OS-level distance filter while moving: a still phone would get no
    // updates at all. Our own LocationFilter drops parked duplicates.
    final distance = parked ? 50 : 0;
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

  final _speed = SpeedEstimator(maxPlausibleKmh: _maxPlausibleKmh);

  Fix _toFix(Position p) {
    final est = _speed.estimate(
      lat: p.latitude,
      lon: p.longitude,
      at: p.timestamp,
      accuracyM: p.accuracy,
      speedMps: p.speed,
      speedAccuracyMps: p.speedAccuracy,
      headingDeg: p.heading,
    );
    return Fix(
      lat: p.latitude,
      lon: p.longitude,
      recordedAt: p.timestamp,
      speedKmh: est.speedKmh,
      headingDeg: est.headingDeg,
      accuracyM: p.accuracy > 0 ? p.accuracy : null,
      altitudeM: p.altitude != 0 ? p.altitude : null,
    );
  }

  int _fixes = 0;

  Future<void> _onFix(Fix f) async {
    _lastFixReceivedAt = DateTime.now();
    if (_fixes++ % 30 == 0) _log('fix #$_fixes acc=${f.accuracyM?.round()}m speed=${f.speedKmh?.round()}km/h');

    final decision = _filter.check(f);
    if (decision == FilterDecision.jump) {
      _log('dropped GPS jump to ${f.lat.toStringAsFixed(4)},${f.lon.toStringAsFixed(4)}');
      return; // a glitch: don't show it, move on it, or send it
    }
    if (_motion.update(f)) _listen(); // switch between precise and low-power GPS

    _emit(current.copyWith(
      lat: f.lat,
      lon: f.lon,
      speedKmh: f.speedKmh,
      accuracyM: f.accuracyM,
      lastFixAt: f.recordedAt,
      mode: _motion.mode,
    ));

    if (decision != FilterDecision.accept) return;
    final prev = _lastAccepted;
    _lastAccepted = f;
    await buffer.add(f.toPoint(seq: 0, batteryPct: _batteryPct));
    _emit(current.copyWith(
      queued: current.queued + 1,
      distanceM: current.distanceM + drivenDistanceM(prev, f, maxPlausibleKmh: _maxPlausibleKmh),
    ));
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
        _log('job offer #${msg.jobOffer.number}');
        onJobOffer?.call(msg.jobOffer);
        _emit(current.copyWith(jobSignal: current.jobSignal + 1));
      case ServerMessage_Payload.jobCancelled:
        _log('job cancelled: ${msg.jobCancelled.reason}');
        _emit(current.copyWith(jobSignal: current.jobSignal + 1));
      case ServerMessage_Payload.notSet:
        break;
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
