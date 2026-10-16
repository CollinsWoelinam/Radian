import 'motion.dart';

enum LinkState { offline, connecting, online }

/// Snapshot of the tracker, sent from the background service to the UI as a
/// plain map (it crosses an isolate boundary on Android).
class TrackerStatus {
  const TrackerStatus({
    this.running = false,
    this.link = LinkState.offline,
    this.mode = MotionMode.moving,
    this.queued = 0,
    this.sent = 0,
    this.acked = 0,
    this.lat,
    this.lon,
    this.speedKmh,
    this.accuracyM,
    this.lastFixAt,
    this.error,
    this.authExpired = false,
    this.startedAt,
    this.distanceM = 0,
    this.jobSignal = 0,
  });

  final bool running;
  final LinkState link;
  final MotionMode mode;
  final int queued;
  final int sent;
  final int acked;
  final double? lat;
  final double? lon;
  final double? speedKmh;
  final double? accuracyM;
  final DateTime? lastFixAt;
  /// Set when tracking stopped for a reason the driver must act on.
  final String? error;
  /// The device token was rejected; the driver must sign in again.
  final bool authExpired;
  /// When the shift started (survives resumes).
  final DateTime? startedAt;
  /// Distance covered by accepted fixes since the tracker started.
  final double distanceM;
  /// Bumped whenever dispatch pushes a job offer or cancellation; the UI
  /// refetches the current job when it changes.
  final int jobSignal;

  TrackerStatus copyWith({
    bool? running,
    LinkState? link,
    MotionMode? mode,
    int? queued,
    int? sent,
    int? acked,
    double? lat,
    double? lon,
    double? speedKmh,
    double? accuracyM,
    DateTime? lastFixAt,
    String? error,
    DateTime? startedAt,
    double? distanceM,
    int? jobSignal,
  }) =>
      TrackerStatus(
        running: running ?? this.running,
        link: link ?? this.link,
        mode: mode ?? this.mode,
        queued: queued ?? this.queued,
        sent: sent ?? this.sent,
        acked: acked ?? this.acked,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        speedKmh: speedKmh ?? this.speedKmh,
        accuracyM: accuracyM ?? this.accuracyM,
        lastFixAt: lastFixAt ?? this.lastFixAt,
        error: error ?? this.error,
        authExpired: authExpired,
        startedAt: startedAt ?? this.startedAt,
        distanceM: distanceM ?? this.distanceM,
        jobSignal: jobSignal ?? this.jobSignal,
      );

  Map<String, dynamic> toMap() => {
        'running': running,
        'link': link.index,
        'mode': mode.index,
        'queued': queued,
        'sent': sent,
        'acked': acked,
        'lat': lat,
        'lon': lon,
        'speedKmh': speedKmh,
        'accuracyM': accuracyM,
        'lastFixAt': lastFixAt?.millisecondsSinceEpoch,
        'error': error,
        'authExpired': authExpired,
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'distanceM': distanceM,
        'jobSignal': jobSignal,
      };

  factory TrackerStatus.fromMap(Map<String, dynamic> m) => TrackerStatus(
        running: m['running'] as bool? ?? false,
        link: LinkState.values[m['link'] as int? ?? 0],
        mode: MotionMode.values[m['mode'] as int? ?? 0],
        queued: m['queued'] as int? ?? 0,
        sent: m['sent'] as int? ?? 0,
        acked: m['acked'] as int? ?? 0,
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        speedKmh: (m['speedKmh'] as num?)?.toDouble(),
        accuracyM: (m['accuracyM'] as num?)?.toDouble(),
        lastFixAt: m['lastFixAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['lastFixAt'] as int),
        error: m['error'] as String?,
        authExpired: m['authExpired'] as bool? ?? false,
        startedAt: m['startedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['startedAt'] as int),
        distanceM: (m['distanceM'] as num?)?.toDouble() ?? 0,
        jobSignal: m['jobSignal'] as int? ?? 0,
      );
}
