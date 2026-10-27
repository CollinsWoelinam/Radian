import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' show Permission, PermissionActions, openAppSettings;

import '../auth/session.dart';
import '../jobs/driver_job.dart';
import '../tracking/host.dart';
import '../tracking/motion.dart';
import '../tracking/permissions.dart';
import '../tracking/readiness.dart';
import '../tracking/status.dart';
import 'job_card.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session, required this.onSignedOut});

  final Session session;
  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _host = TrackerHost.instance;
  TrackerStatus _status = const TrackerStatus();
  StreamSubscription<TrackerStatus>? _sub;
  Timer? _clock;
  bool _busy = false;
  ReadinessReport? _readiness;
  // Set when a shift was in progress but tracking isn't running (app killed).
  bool _interrupted = false;
  // Largest backlog seen since it was last empty, for the upload progress bar.
  int _backlogPeak = 0;

  // Dispatch: the current offer or job. Pushed offers bump jobSignal; a poll
  // covers anything missed while offline.
  DriverJob? _job;
  bool _jobBusy = false;
  int _lastJobSignal = 0;
  Timer? _jobPoll;
  Timer? _offerExpiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _host.status.listen(_onStatus);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // "updated 4s ago", shift timer
    });
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _clock?.cancel();
    _jobPoll?.cancel();
    _offerExpiry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back from Settings: the checklist may have changed. Back from the map
    // app: the job may have moved on.
    if (_status.running) {
      _refreshJob();
    } else {
      _recheck();
    }
  }

  void _onStatus(TrackerStatus s) {
    if (s.authExpired) {
      _signOut(); // token rejected mid-shift: back to the login screen
      return;
    }
    if (!mounted) return;
    final wasRunning = _status.running;
    setState(() {
      _status = s;
      if (s.running) _interrupted = false;
      _backlogPeak = s.queued == 0 ? 0 : (s.queued > _backlogPeak ? s.queued : _backlogPeak);
    });
    if (s.running && !wasRunning) _startJobPolling();
    if (!s.running && wasRunning) _stopJobPolling();
    if (s.jobSignal != _lastJobSignal) {
      _lastJobSignal = s.jobSignal;
      _refreshJob();
    }
    if (!s.running) _recheck();
  }

  // --- Dispatch ---------------------------------------------------------------

  void _startJobPolling() {
    _refreshJob();
    _jobPoll?.cancel();
    _jobPoll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshJob());
  }

  void _stopJobPolling() {
    _jobPoll?.cancel();
    _offerExpiry?.cancel();
    if (mounted) setState(() => _job = null);
  }

  Future<void> _refreshJob() async {
    try {
      final job = await DriverJobApi.current();
      if (!mounted) return;
      final isNewOffer = job != null && job.isOffer && job.id != _job?.id;
      setState(() => _job = job);
      if (isNewOffer) HapticFeedback.heavyImpact();
      // Drop the offer card the moment it lapses.
      _offerExpiry?.cancel();
      if (job?.offerExpiresAt != null) {
        final left = job!.offerExpiresAt!.difference(DateTime.now()) + const Duration(milliseconds: 500);
        _offerExpiry = Timer(left.isNegative ? Duration.zero : left, _refreshJob);
      }
    } catch (_) {
      // Offline or server hiccup: keep showing what we have; the next poll retries.
    }
  }

  Future<void> _jobAction(Future<void> Function() action, {String? done}) async {
    setState(() => _jobBusy = true);
    try {
      await action();
      if (done != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } on JobActionException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      await _refreshJob();
      if (mounted) setState(() => _jobBusy = false);
    }
  }

  /// On launch: pick up a running tracker, or resume a shift that was cut
  /// short (app or service killed) if permissions still allow it.
  Future<void> _restore() async {
    final running = await _host.isRunning();
    if (running) {
      if (mounted) setState(() => _status = _status.copyWith(running: true));
      _startJobPolling();
      return;
    }
    await _recheck();
    // Re-check after the (slow) readiness probe: the driver may have tapped
    // "Start shift" meanwhile, which also records a shift start.
    if (await ShiftStore.startedAt() == null || await _host.isRunning() || _busy) return;
    if (_readiness?.canStart ?? false) {
      await _host.start();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift resumed. Tracking is back on.')));
      }
    } else if (mounted) {
      setState(() => _interrupted = true);
    }
  }

  Future<void> _recheck() async {
    final r = await Readiness.check();
    if (mounted) setState(() => _readiness = r);
  }

  Future<void> _startShift() async {
    setState(() => _busy = true);
    try {
      final problem = await TrackingPermissions.ensure();
      if (problem != null) {
        if (mounted) _explainPermission(problem);
        return;
      }
      HapticFeedback.mediumImpact();
      await _host.start();
    } finally {
      if (mounted) setState(() => _busy = false);
      _recheck();
    }
  }

  Future<void> _endShift() async {
    final job = _job;
    if (job != null && !job.isOffer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finish job #${job.number} before ending your shift, or ask dispatch to cancel it.')),
      );
      return;
    }
    final s = _status;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End shift?'),
        content: Text([
          'You\'ve been on shift ${_duration(s.startedAt)} and driven ${_km(s.distanceM)}.',
          if (s.queued > 0)
            '${s.queued} location updates are still saved on this phone. They\'ll upload next time you\'re online.',
          'Dispatch will stop seeing your vehicle.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep driving')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End shift'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      HapticFeedback.mediumImpact();
      await _host.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _explainPermission(PermissionProblem p) {
    final text = switch (p) {
      PermissionProblem.servicesOff => 'Location is turned off on this phone. Turn it on to start your shift.',
      PermissionProblem.denied => 'Radian needs your location while you are on shift so dispatch can see your vehicle.',
      PermissionProblem.deniedForever => 'Location access is blocked for Radian. Allow it in Settings to start your shift.',
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location needed'),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              Navigator.pop(ctx);
              if (p == PermissionProblem.denied) {
                _startShift();
              } else {
                TrackingPermissions.openSettings(p);
              }
            },
            child: Text(p == PermissionProblem.denied ? 'Try again' : 'Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(CheckAction a) async {
    switch (a) {
      case CheckAction.enableLocation:
        await Geolocator.openLocationSettings();
      case CheckAction.grantLocation:
        await Geolocator.requestPermission();
      case CheckAction.openAppSettings:
        await Geolocator.openAppSettings();
      case CheckAction.grantNotifications:
        await Permission.notification.request();
      case CheckAction.allowBackground:
        await Permission.ignoreBatteryOptimizations.request();
      case CheckAction.phoneSetup:
        await _showPhoneSetup();
    }
    await _recheck();
  }

  Future<void> _showPhoneSetup() async {
    final maker = await Readiness.manufacturer();
    if (!mounted) return;
    final steps = Readiness.phoneSetupSteps(maker);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Keep Radian running', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Your phone closes apps in the background to save battery. Do this once so tracking keeps going during shifts.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              for (final (i, step) in steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    const SizedBox(width: 12),
                    Expanded(child: Text(step)),
                  ]),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: openAppSettings,
                child: const Text('Open Radian settings'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await Readiness.markPhoneSetupDone();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('I\'ve done this'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await ShiftStore.end();
    await SessionStore.clear();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _status;
    final onShift = s.running;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          const RadianMark(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.session.plate, style: mono(theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${widget.session.driverName} · ${_kind(widget.session.vehicleKind)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) => _signOut(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'signout',
                enabled: !onShift,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  subtitle: onShift ? const Text('End your shift first') : null,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _recheck,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (onShift) ...[
                _ShiftHero(status: s),
                if (_job != null) ...[
                  const SizedBox(height: 12),
                  JobCard(
                    job: _job!,
                    busy: _jobBusy,
                    onAccept: () => _jobAction(() => DriverJobApi.accept(_job!.id), done: 'Job accepted. Head to the pickup.'),
                    onDecline: () => _jobAction(() => DriverJobApi.decline(_job!.id)),
                    onAdvance: (st) => _jobAction(
                      () => DriverJobApi.setStatus(_job!.id, st),
                      done: st == 'COMPLETED' ? 'Job complete. Nice work.' : null,
                    ),
                  ),
                ],
                if (_backlogPeak >= 10 && s.queued > 0) ...[
                  const SizedBox(height: 12),
                  _UploadBanner(status: s, peak: _backlogPeak),
                ],
              ] else
                _OffHero(readiness: _readiness, interrupted: _interrupted),
              if (s.error != null) ...[
                const SizedBox(height: 12),
                _Banner(text: s.error!),
              ],
              const SizedBox(height: 16),
              if (onShift) _ShiftStats(status: s) else _Checklist(report: _readiness, onAction: _runAction),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: onShift
            ? FilledButton.icon(
                onPressed: _busy ? null : _endShift,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End shift'),
              )
            : FilledButton.icon(
                onPressed: _busy ? null : _startShift,
                icon: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.play_circle_outline),
                label: Text(_interrupted ? 'Resume shift' : 'Start shift'),
              ),
      ),
    );
  }
}

// --- Off shift --------------------------------------------------------------

class _OffHero extends StatelessWidget {
  const _OffHero({required this.readiness, required this.interrupted});

  final ReadinessReport? readiness;
  final bool interrupted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = readiness;
    final (title, subtitle) = interrupted
        ? ('Shift interrupted', 'Tracking stopped unexpectedly. Fix the items below, then resume.')
        : r == null
            ? ('Off shift', 'Checking your phone…')
            : !r.canStart
                ? ('Off shift', 'Fix the items marked red to start your shift.')
                : r.warnings > 0
                    ? ('Off shift', 'Ready to go. ${r.warnings == 1 ? 'One tip' : '${r.warnings} tips'} below for reliable tracking.')
                    : ('Off shift', 'All set. Start your shift to share your location with dispatch.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          _Pulse(color: interrupted ? warnAmber : theme.colorScheme.outline, active: false),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.report, required this.onAction});

  final ReadinessReport? report;
  final Future<void> Function(CheckAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Before you start', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (r == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            for (final item in r.items)
              ListTile(
                leading: _CheckIcon(state: item.state),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(item.detail),
                trailing: item.action == null
                    ? null
                    : TextButton(onPressed: () => onAction(item.action!), child: Text(item.actionLabel ?? 'Fix')),
              ),
        ]),
      ),
    );
  }
}

class _CheckIcon extends StatelessWidget {
  const _CheckIcon({required this.state});
  final CheckState state;

  @override
  Widget build(BuildContext context) => switch (state) {
        CheckState.ok => const Icon(Icons.check_circle, color: liveGreen, semanticLabel: 'OK'),
        CheckState.warn => const Icon(Icons.error_outline, color: warnAmber, semanticLabel: 'Recommended'),
        CheckState.fail => const Icon(Icons.cancel, color: failRed, semanticLabel: 'Required'),
      };
}

// --- On shift ---------------------------------------------------------------

class _ShiftHero extends StatelessWidget {
  const _ShiftHero({required this.status});

  final TrackerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final live = s.link == LinkState.online;
    // On shift, the driver is the live vehicle: the mark's amber dot.
    final color = live ? liveAmber : theme.colorScheme.outline;
    final title = live ? 'On shift · Live' : (s.link == LinkState.connecting ? 'On shift · Connecting' : 'On shift · Offline');
    final updated = s.lastFixAt == null ? 'Waiting for GPS…' : 'Updated ${_ago(s.lastFixAt)}';
    final subtitle = live
        ? 'Dispatch can see your vehicle. $updated'
        : 'No connection. Your route is saved on this phone and uploads automatically.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          _Pulse(color: color, active: live),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _UploadBanner extends StatelessWidget {
  const _UploadBanner({required this.status, required this.peak});

  final TrackerStatus status;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = status.link == LinkState.online;
    final done = peak - status.queued;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                online ? 'Uploading your saved route… $done of $peak' : '${status.queued} location updates saved on this phone',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: online ? done / peak : null,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          if (!online) ...[
            const SizedBox(height: 8),
            Text('They\'ll upload as soon as you have signal.', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class _ShiftStats extends StatelessWidget {
  const _ShiftStats({required this.status});

  final TrackerStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _Tile(icon: Icons.timer_outlined, label: 'On shift', value: _duration(s.startedAt), detail: 'since ${_clockTime(s.startedAt)}'),
        _Tile(icon: Icons.route_outlined, label: 'Distance', value: _km(s.distanceM), detail: 'this shift'),
        _Tile(
          icon: Icons.speed,
          label: 'Speed',
          // Below walking-to-driving pace it's GPS noise, not motion.
          value: s.speedKmh == null ? '—' : '${s.speedKmh! < 5 ? 0 : s.speedKmh!.round()} km/h',
          detail: s.mode == MotionMode.parked
              ? 'Parked · saving battery'
              : (s.speedKmh ?? 0) >= 5
                  ? 'Moving'
                  : 'Stopped',
        ),
        _Tile(
          icon: Icons.gps_fixed,
          label: 'GPS',
          value: s.accuracyM == null ? '—' : '± ${s.accuracyM!.round()} m',
          detail: '${s.acked} delivered',
        ),
      ],
    );
  }
}

// --- Shared -----------------------------------------------------------------

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.active) _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
            Container(
              width: 18 + 26 * _ctrl.value,
              height: 18 + 26 * _ctrl.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _ctrl.value))),
            ),
          Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, required this.detail});

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: mono(theme.textTheme.titleLarge).copyWith(fontWeight: FontWeight.w600)),
            ),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.error_outline, color: scheme.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}

String _ago(DateTime? t) {
  if (t == null) return '—';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  return '${s ~/ 3600}h ago';
}

String _duration(DateTime? since) {
  if (since == null) return '—';
  final d = DateTime.now().difference(since);
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

String _clockTime(DateTime? t) =>
    t == null ? '—' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _km(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String _kind(String k) => switch (k) {
      'MOTORBIKE' => 'Motorbike',
      'AMBULANCE' => 'Ambulance',
      'VAN' => 'Van',
      'TRUCK' => 'Truck',
      _ => 'Car',
    };
