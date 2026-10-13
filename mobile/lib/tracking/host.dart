import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../auth/session.dart';
import '../config.dart';
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
  Future<void> start();
  Future<void> stop();
  Stream<TrackerStatus> get status;
}

// --- Android ----------------------------------------------------------------

const _channelId = 'radian_tracking';
const _notificationId = 4207;

class AndroidTrackerHost implements TrackerHost {
  final _service = FlutterBackgroundService();

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
  }

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<void> start() async {
    await _service.startService();
  }

  @override
  Future<void> stop() async {
    _service.invoke('stop');
  }

  @override
  Stream<TrackerStatus> get status {
    // Ask a running service to repeat its latest status for a freshly opened UI.
    Future.delayed(const Duration(milliseconds: 100), () => _service.invoke('status_request'));
    return _service.on('status').where((m) => m != null).map((m) => TrackerStatus.fromMap(m!));
  }
}

/// Entry point of the Android foreground service isolate.
@pragma('vm:entry-point')
Future<void> trackingServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final session = await SessionStore.load();
  if (session == null) {
    service.invoke('status', const TrackerStatus(error: 'Sign in to start a shift.', authExpired: true).toMap());
    await service.stopSelf();
    return;
  }

  final engine = TrackingEngine(
    token: session.token,
    ingestUrl: AppConfig.ingestUrl,
    buffer: await PointBuffer.open(),
  );

  String? lastNotice;
  engine.status.listen((s) {
    service.invoke('status', s.toMap());
    final notice = _notificationText(s, session.plate);
    if (service is AndroidServiceInstance && notice != lastNotice) {
      lastNotice = notice;
      service.setForegroundNotificationInfo(title: 'On shift · ${session.plate}', content: notice);
    }
    if (!s.running && s.error != null) service.stopSelf();
  });

  service.on('status_request').listen((_) => service.invoke('status', engine.current.toMap()));
  service.on('stop').listen((_) async {
    await engine.stop();
    service.invoke('status', engine.current.toMap());
    await service.stopSelf();
  });

  await engine.start();
}

String _notificationText(TrackerStatus s, String plate) {
  final link = switch (s.link) {
    LinkState.online => 'Live',
    LinkState.connecting => 'Connecting',
    LinkState.offline => s.queued > 0 ? 'Offline · ${s.queued} queued' : 'Offline',
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

  @override
  Future<void> start() async {
    if (_engine != null) return;
    final session = await SessionStore.load();
    if (session == null) {
      _status.add(const TrackerStatus(error: 'Sign in to start a shift.', authExpired: true));
      return;
    }
    final engine = TrackingEngine(
      token: session.token,
      ingestUrl: AppConfig.ingestUrl,
      buffer: await PointBuffer.open(),
    );
    _engine = engine;
    _sub = engine.status.listen((s) {
      _status.add(s);
      if (!s.running && s.error != null) _teardown();
    });
    await engine.start();
  }

  @override
  Future<void> stop() async {
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
