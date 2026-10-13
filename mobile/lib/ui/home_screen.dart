import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/session.dart';
import '../tracking/host.dart';
import '../tracking/motion.dart';
import '../tracking/permissions.dart';
import '../tracking/status.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session, required this.onSignedOut});

  final Session session;
  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _host = TrackerHost.instance;
  TrackerStatus _status = const TrackerStatus();
  StreamSubscription<TrackerStatus>? _sub;
  Timer? _clock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = _host.status.listen((s) {
      if (s.authExpired) {
        _signOut(); // token expired mid-shift: back to the login screen
        return;
      }
      setState(() => _status = s);
    });
    _host.isRunning().then((r) {
      if (mounted && r != _status.running) setState(() => _status = _status.copyWith(running: r));
    });
    // Re-render "last fix 4s ago" every second.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _toggleShift() async {
    setState(() => _busy = true);
    try {
      if (_status.running) {
        await _host.stop();
        return;
      }
      final problem = await TrackingPermissions.ensure();
      if (problem != null) {
        if (mounted) _explainPermission(problem);
        return;
      }
      await _host.start();
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
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () {
              Navigator.pop(ctx);
              if (p == PermissionProblem.denied) {
                _toggleShift();
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

  Future<void> _signOut() async {
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
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.plate, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              '${widget.session.driverName} · ${_kind(widget.session.vehicleKind)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) => _signOut(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'signout', enabled: !onShift, child: const Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _ShiftHero(status: s),
            if (s.error != null) ...[
              const SizedBox(height: 12),
              _Banner(text: s.error!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _toggleShift,
              style: onShift
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    )
                  : null,
              icon: Icon(onShift ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              label: Text(onShift ? 'End shift' : 'Start shift'),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _Tile(
                  icon: Icons.cell_tower,
                  label: 'Connection',
                  value: switch (s.link) {
                    LinkState.online => 'Live',
                    LinkState.connecting => 'Connecting',
                    LinkState.offline => onShift ? 'No signal' : 'Off',
                  },
                  detail: s.queued > 0 ? '${s.queued} points queued' : 'Nothing queued',
                  color: !onShift ? null : (s.link == LinkState.online ? liveGreen : warnAmber),
                ),
                _Tile(
                  icon: Icons.gps_fixed,
                  label: 'GPS',
                  value: s.accuracyM == null ? '—' : '± ${s.accuracyM!.round()} m',
                  detail: s.mode == MotionMode.parked ? 'Parked · power saving' : 'High precision',
                ),
                _Tile(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: s.speedKmh == null ? '—' : '${s.speedKmh!.round()} km/h',
                  detail: s.lat == null ? 'Waiting for GPS' : '${s.lat!.toStringAsFixed(5)}, ${s.lon!.toStringAsFixed(5)}',
                ),
                _Tile(
                  icon: Icons.schedule,
                  label: 'Last fix',
                  value: _ago(s.lastFixAt),
                  detail: '${s.acked} delivered',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftHero extends StatelessWidget {
  const _ShiftHero({required this.status});

  final TrackerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = status.running;
    final live = on && status.link == LinkState.online;
    final color = !on ? theme.colorScheme.outline : (live ? liveGreen : warnAmber);
    final title = !on ? 'Off shift' : (live ? 'On shift · Live' : 'On shift · Offline');
    final subtitle = !on
        ? 'Start your shift to share your location with dispatch.'
        : live
            ? 'Dispatch can see your vehicle in real time.'
            : 'No connection. Your route is saved and will upload automatically.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _Pulse(color: color, active: live),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.active) _ctrl.stop();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
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
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 18 + 26 * _ctrl.value,
                height: 18 + 26 * _ctrl.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _ctrl.value))),
              ),
            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, required this.detail, this.color});

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? color;

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
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
  if (s < 5) return 'Just now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  return '${s ~/ 3600}h ago';
}

String _kind(String k) => switch (k) {
      'MOTORBIKE' => 'Motorbike',
      'AMBULANCE' => 'Ambulance',
      'VAN' => 'Van',
      'TRUCK' => 'Truck',
      _ => 'Car',
    };
