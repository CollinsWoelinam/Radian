import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' show Permission, PermissionActions, openAppSettings;

import '../auth/session.dart';
import '../jobs/driver_job.dart';
import '../shifts/shift_api.dart';
import '../tracking/host.dart';
import '../tracking/permissions.dart';
import '../tracking/readiness.dart';
import '../tracking/status.dart';
import 'format.dart';
import 'shift_views.dart';
import 'tab_bar.dart';
import 'tabs.dart';

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

  int _tab = 0;
  // This shift's server record and the jobs completed in it.
  String? _shiftId;
  ShiftDetail? _today;
  int _historyKey = 0;

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
    if (s.running && !wasRunning) {
      _startJobPolling();
      _openShift();
    }
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

  /// Records the shift on the server (best effort: ending it also creates it).
  Future<void> _openShift() async {
    final started = await ShiftStore.startedAt();
    if (started == null) return;
    try {
      final s = await ShiftApi.start(started);
      _shiftId = s.id;
      await _refreshToday();
    } catch (_) {}
  }

  Future<void> _refreshToday() async {
    try {
      var id = _shiftId;
      if (id == null) {
        final recent = await ShiftApi.list(limit: 1);
        if (recent.isEmpty) return;
        id = recent.first.id;
      }
      final d = await ShiftApi.get(id);
      if (mounted) setState(() => _today = d);
    } catch (_) {}
  }

  Future<void> _jobAction(Future<void> Function() action, {String? done}) async {
    setState(() => _jobBusy = true);
    try {
      await action();
      if (done != null) _refreshToday();
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
      _openShift();
      return;
    }
    _refreshToday();
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
          'You\'ve been on shift ${sinceText(s.startedAt)} and driven ${km(s.distanceM)}.',
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
    final started = s.startedAt ?? await ShiftStore.startedAt() ?? DateTime.now();
    try {
      HapticFeedback.mediumImpact();
      await _host.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // The server works out the shift's distance and jobs from what it received.
    ShiftDetail? detail;
    try {
      detail = await ShiftApi.end(started, DateTime.now());
    } catch (_) {}
    _shiftId = null;
    if (!mounted) return;
    setState(() {
      _historyKey++;
      if (detail != null) _today = detail;
    });
    if (detail != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShiftSummaryScreen(detail: detail!, justEnded: true)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift ended after ${durationText(DateTime.now().difference(started))}. The summary will be in History once you\'re online.')),
      );
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
    final s = _status;
    final onShift = s.running;
    final job = _job;
    final offer = onShift && job != null && job.isOffer;

    final Widget shiftTab = !onShift
        ? OffShiftView(
            session: widget.session,
            readiness: _readiness,
            interrupted: _interrupted,
            busy: _busy,
            onStart: _startShift,
            onAction: _runAction,
            onRefresh: _recheck,
          )
        : job != null && !job.isOffer
            ? NavigateView(
                job: job,
                status: s,
                busy: _jobBusy,
                onAdvance: (st) => _jobAction(
                  () => DriverJobApi.setStatus(job.id, st),
                  done: st == 'COMPLETED' ? 'Job complete. Nice work.' : null,
                ),
              )
            : LiveView(
                session: widget.session,
                status: s,
                jobsDone: _today?.jobs.length,
                backlogPeak: _backlogPeak,
                busy: _busy,
                onEnd: _endShift,
              );

    return Scaffold(
      body: Stack(children: [
        IndexedStack(index: _tab, children: [
          shiftTab,
          JobsTab(
            job: job,
            onShift: onShift,
            today: _today,
            onShowJob: () => setState(() => _tab = 0),
            onRefresh: () async {
              await _refreshJob();
              await _refreshToday();
            },
          ),
          HistoryTab(refreshKey: _historyKey),
          ProfileTab(session: widget.session, onShift: onShift, onSignOut: _signOut, onPhoneSetup: _showPhoneSetup),
        ]),
        // An offer takes the whole screen, whatever tab is open.
        if (offer)
          Positioned.fill(
            child: OfferView(
              key: ValueKey(job.id),
              job: job,
              busy: _jobBusy,
              onAccept: () => _jobAction(() => DriverJobApi.accept(job.id)), // the screen itself changes to the job
              onDecline: () => _jobAction(() => DriverJobApi.decline(job.id)),
            ),
          ),
      ]),
      bottomNavigationBar: offer
          ? null
          : RadianTabBar(
              index: _tab,
              live: onShift,
              onSelect: (i) {
                setState(() => _tab = i);
                if (i == 1) _refreshToday();
              },
              items: [
                const TabItem(TabIcon.shift, 'Shift'),
                TabItem(TabIcon.jobs, 'Jobs', badge: job != null && _tab != 1),
                const TabItem(TabIcon.history, 'History'),
                const TabItem(TabIcon.profile, 'Profile'),
              ],
            ),
    );
  }
}
