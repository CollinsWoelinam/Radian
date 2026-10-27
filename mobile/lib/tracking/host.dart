import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../auth/session.dart';
import '../config.dart';
import '../gen/radian/telemetry/v1/telemetry.pb.dart';
import 'engine.dart';
import 'motion.dart';
import 'point_buffer.dart';
import 'status.dart';

/// Where the tracking engine runs.
///
/// Android: a foreground service with its own Dart isolate and a persistent
/// notification, so tracking survives the app being swiped away and Android's
/// background execution limits.
///
/// iOS: there are no foreground services; the engine runs in the app process
/// and iOS keeps it alive while background location updates are active.
abstract class TrackerHost {
  static final TrackerHost instance = Platform.isAndroid ? AndroidTrackerHost() : InProcessTrackerHost();

  Future<void> init();
  Future<bool> isRunning();

  /// Starts (or resumes) the shift.
  Future<void> start();

  /// Ends the shift at the driver's request.
  Future<void> stop();

  Stream<TrackerStatus> get status;
}

Future<TrackingEngine> _newEngine(Session session, {void Function(JobOffer)? onJobOffer}) async => TrackingEngine(
      token: session.token,
      ingestUrl: AppConfig.ingestUrl,
      buffer: await PointBuffer.open(),
      startedAt: await ShiftStore.startedAt(),
      refreshToken: SessionStore.freshToken,
      onJobOffer: onJobOffer,
    );

// --- Android ----------------------------------------------------------------

const _channelId = 'radian_tracking';
const _notificationId = 4207;
const _jobsChannelId = 'radian_jobs';
const _jobNotificationId = 4208;

class AndroidTrackerHost implements TrackerHost {
  final _service = FlutterBackgroundService();
  final _status = StreamController<TrackerStatus>.broadcast();
  TrackerStatus _last = const TrackerStatus();

  @override
  Future<void> init() async {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Shift tracking',
          description: 'Shown while your location is shared during a shift.',
          importance: Importance.low,
        ));
    await notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _jobsChannelId,
          'Job offers',
          description: 'New jobs from dispatch. You have about 30 seconds to accept.',
          importance: Importance.high,
        ));

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: trackingServiceMain,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
        initialNotificationTitle: 'Radian',
        initialNotificationContent: 'Starting shift…',
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    // One subscription for the app's lifetime; screens listen to _status.
    _service.on('status').listen((m) {
      if (m == null) return;
      _last = TrackerStatus.fromMap(m);
      _status.add(_last);
    });
  }

  @override
  Future<bool> isRunning() => _service.isRunning();

  Future<void>? _starting;

  /// Idempotent: concurrent calls share one start.
  @override
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    await ShiftStore.begin();
    if (await _service.isRunning()) return;
    await _service.startService();
  }

  @override
  Future<void> stop() async {
    await ShiftStore.end();
    _service.invoke('stop');
    // The service's final status message can be lost when it shuts down, so
    // confirm the stop by polling instead of waiting for that message.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) && await _service.isRunning()) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (_last.running) {
      _last = _last.copyWith(running: false, link: LinkState.offline);
      _status.add(_last);
    }
  }

  @override
  Stream<TrackerStatus> get status {
    // Ask a running service to repeat its latest status for a freshly opened UI.
    Future.delayed(const Duration(milliseconds: 100), () => _service.invoke('status_request'));
    return _status.stream;
  }
}

/// Entry point of the Android foreground service isolate.
@pragma('vm:entry-point')
Future<void> trackingServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Android may restart a killed service on its own; only track if the
  // driver is actually on shift.
  final session = await SessionStore.load();
  final onShift = await ShiftStore.startedAt() != null;
  if (session == null || !onShift) {
    debugPrint('[radian.tracker] service: not on shift, stopping');
    if (session == null) {
      service.invoke('status', const TrackerStatus(error: 'Sign in to start a shift.', authExpired: true).toMap());
    }
    await service.stopSelf();
    return;
  }

  // Heads-up notification for offers, so a driver with the app in the
  // background still sees them in time. Tapping it opens the app.
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_bg_service_small')),
  );
  final engine = await _newEngine(session, onJobOffer: (offer) {
    final where = offer.pickupAddress.isNotEmpty ? offer.pickupAddress : 'a pickup nearby';
    final mins = (offer.etaSeconds / 60).ceil();
    notifications.show(
      id: _jobNotificationId,
      title: '${offer.priority <= 2 ? 'URGENT job' : 'New job'} #${offer.number}',
      body: '$where · $mins min away. Open Radian to accept.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _jobsChannelId,
          'Job offers',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          color: Color(0xFF2563EB), // Radian Blue
          timeoutAfter: 30000,
        ),
      ),
    );
  });

  String? lastNotice;
  engine.status.listen((s) {
    service.invoke('status', s.toMap());
    final notice = _notificationText(s);
    if (service is AndroidServiceInstance && notice != lastNotice) {
      lastNotice = notice;
      service.setForegroundNotificationInfo(title: 'On shift · ${session.plate}', content: notice);
    }
    if (!s.running && s.error != null) {
      ShiftStore.end();
      service.stopSelf();
    }
  });

  service.on('status_request').listen((_) => service.invoke('status', engine.current.toMap()));
  service.on('stop').listen((_) async {
    debugPrint('[radian.tracker] service: stop received');
    await engine.stop();
    service.invoke('status', engine.current.toMap());
    // Give the final status a moment to reach the app before the isolate dies.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    debugPrint('[radian.tracker] service: stopping self');
    await service.stopSelf();
  });

  await engine.start();
}

String _notificationText(TrackerStatus s) {
  final link = switch (s.link) {
    LinkState.online => 'Live',
    LinkState.connecting => 'Connecting',
    LinkState.offline => s.queued > 0 ? 'Offline · ${s.queued} saved' : 'Offline',
  };
  final mode = s.mode == MotionMode.parked ? 'Parked · saving battery' : 'Sharing location';
  return '$link · $mode';
}

// --- iOS (and anything else) -----------------------------------------------

class InProcessTrackerHost implements TrackerHost {
  TrackingEngine? _engine;
  final _status = StreamController<TrackerStatus>.broadcast();
  StreamSubscription? _sub;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isRunning() async => _engine?.current.running ?? false;

  Future<void>? _starting;

  /// Idempotent: concurrent calls share one start, so two engines can never
  /// write to the same outbox.
  @override
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_engine != null) return;
    final session = await SessionStore.load();
    if (session == null) {
      _status.add(const TrackerStatus(error: 'Sign in to start a shift.', authExpired: true));
      return;
    }
    await ShiftStore.begin();
    final engine = await _newEngine(session);
    _engine = engine;
    _sub = engine.status.listen((s) {
      _status.add(s);
      if (!s.running && s.error != null) {
        ShiftStore.end();
        _teardown();
      }
    });
    await engine.start();
  }

  @override
  Future<void> stop() async {
    await ShiftStore.end();
    final engine = _engine;
    if (engine == null) return;
    await engine.stop();
    // Forward the final state directly: the engine's broadcast stream delivers
    // asynchronously, and _teardown cancels that subscription right away.
    _status.add(engine.current);
    await _teardown();
  }

  Future<void> _teardown() async {
    final engine = _engine;
    _engine = null;
    await _sub?.cancel();
    await engine?.buffer.close();
  }

  @override
  Stream<TrackerStatus> get status {
    final e = _engine;
    if (e != null) scheduleMicrotask(() => _status.add(e.current));
    return _status.stream;
  }
}
