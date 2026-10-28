import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session.dart';
import '../jobs/driver_job.dart';
import '../tracking/motion.dart';
import '../tracking/readiness.dart';
import '../tracking/status.dart';
import 'format.dart';
import 'map_view.dart';
import 'theme.dart';

// --- Off shift ----------------------------------------------------------------

/// Before a shift: greeting, a readiness ring and the checklist.
class OffShiftView extends StatelessWidget {
  const OffShiftView({
    super.key,
    required this.session,
    required this.readiness,
    required this.interrupted,
    required this.busy,
    required this.onStart,
    required this.onAction,
    required this.onRefresh,
  });

  final Session session;
  final ReadinessReport? readiness;
  final bool interrupted;
  final bool busy;
  final VoidCallback onStart;
  final Future<void> Function(CheckAction) onAction;
  final Future<void> Function() onRefresh;

  String get _greeting {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    return '$part, ${session.driverName.split(' ').first}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = readiness;
    final total = r?.items.length ?? 0;
    final ok = r?.items.where((i) => i.state == CheckState.ok).length ?? 0;
    final (title, subtitle) = interrupted
        ? ('Shift interrupted', 'Tracking stopped unexpectedly. Fix the items below, then resume.')
        : r == null
        ? ('Checking your phone…', 'This takes a moment.')
        : !r.canStart
        ? ('Not ready yet', 'Fix the items marked red to start your shift.')
        : r.warnings > 0
        ? ('Almost ready', '${r.warnings == 1 ? 'One tip' : '${r.warnings} tips'} left for reliable tracking. You can still start.')
        : ('Ready to go', 'Start your shift to share your location with dispatch.');

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(
              children: [
                const RadianMark(size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Text(session.plate, style: mono(theme.textTheme.bodySmall).copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          Text(
                            ' · ${vehicleKind(session.vehicleKind)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const StatusPill(label: 'Off shift'),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    // Night Ink on light; a raised surface on dark, where the page is already ink.
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark ? theme.colorScheme.surface : nightInk,
                    borderRadius: BorderRadius.circular(22),
                    border: theme.brightness == Brightness.dark ? Border.all(color: theme.dividerColor) : null,
                  ),
                    child: Row(
                      children: [
                        ReadinessRing(done: ok, total: total),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(color: Color(0xFFF3F6FA), fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(subtitle, style: const TextStyle(color: Color(0xFF9AA6B8), fontSize: 13, height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('Before you start', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  Card(
                    child: r == null
                        ? const Padding(
                            padding: EdgeInsets.all(28),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            children: [
                              for (final (i, item) in r.items.indexed) ...[
                                if (i > 0) Divider(height: 1, indent: 56, color: theme.dividerColor),
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CheckIcon(state: item.state),
                                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(item.detail),
                                  trailing: item.action == null
                                      ? null
                                      : FilledButton.tonal(
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(0, 40),
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                          ),
                                          onPressed: () => onAction(item.action!),
                                          child: Text(item.actionLabel ?? 'Fix'),
                                        ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: busy ? null : onStart,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(interrupted ? 'Resume shift' : 'Start shift'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "4/5" checks passed, as a ring.
class ReadinessRing extends StatelessWidget {
  const ReadinessRing({super.key, required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : done / total,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              color: signalBlue,
              backgroundColor: const Color(0xFF263247),
            ),
          ),
          Text(
            total == 0 ? '…' : '$done/$total',
            style: const TextStyle(fontFamily: monoFamily, fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFF3F6FA)),
          ),
        ],
      ),
    );
  }
}

class CheckIcon extends StatelessWidget {
  const CheckIcon({super.key, required this.state});
  final CheckState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (state) {
      CheckState.ok => (Icons.check_rounded, liveGreen, 'OK'),
      CheckState.warn => (Icons.priority_high_rounded, warnAmber, 'Recommended'),
      CheckState.fail => (Icons.close_rounded, failRed, 'Required'),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 18, semanticLabel: label),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color, this.onDark = false});
  final String label;
  final Color? color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xEE111A2B) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onDark ? const Color(0xFF263247) : theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color ?? theme.colorScheme.outline,
              shape: BoxShape.circle,
              boxShadow: color == null ? null : [BoxShadow(color: color!.withValues(alpha: 0.35), spreadRadius: 3)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: onDark ? const Color(0xFFF3F6FA) : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// --- On shift, no job -----------------------------------------------------------

/// On shift: the live map with the driver as the amber dot, and the shift's numbers.
class LiveView extends StatelessWidget {
  const LiveView({
    super.key,
    required this.session,
    required this.status,
    required this.jobsDone,
    required this.backlogPeak,
    required this.busy,
    required this.onEnd,
  });

  final Session session;
  final TrackerStatus status;
  final int? jobsDone;
  final int backlogPeak;
  final bool busy;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final live = s.link == LinkState.online;
    final me = s.lat != null && s.lon != null ? LatLon(s.lat!, s.lon!) : null;
    final speed = s.speedKmh == null ? '—' : '${s.speedKmh! < 5 ? 0 : s.speedKmh!.round()} km/h';

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: RadianMap(me: me)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      StatusPill(
                        label: live ? 'On shift · Live' : (s.link == LinkState.connecting ? 'On shift · Connecting' : 'On shift · Offline'),
                        color: live ? liveAmber : null,
                        onDark: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -6))],
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'On shift since ${clockTime(s.startedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Builder(
                          builder: (_) {
                            final t = sinceText(s.startedAt);
                            final style = t.contains(RegExp(r'\d'))
                                ? mono(theme.textTheme.headlineMedium)
                                : theme.textTheme.headlineMedium!;
                            return Text(t, style: style.copyWith(fontWeight: FontWeight.w600));
                          },
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(session.plate, style: mono(theme.textTheme.titleSmall).copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        vehicleKind(session.vehicleKind),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(label: 'Distance', value: km(s.distanceM)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(label: 'Speed', value: speed, detail: s.mode == MotionMode.parked ? 'Parked' : null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(label: 'Jobs', value: jobsDone == null ? '—' : '$jobsDone done'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.gps_fixed, size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    s.accuracyM == null ? 'Waiting for GPS…' : 'GPS ±${s.accuracyM!.round()} m · ',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (s.accuracyM != null)
                    Text('${s.acked} delivered', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  Text(
                    'Updated ${ago(s.lastFixAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (backlogPeak >= 10 && s.queued > 0) ...[const SizedBox(height: 10), UploadBanner(status: s, peak: backlogPeak)],
              if (s.error != null) ...[const SizedBox(height: 10), ErrorBanner(text: s.error!)],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    const RadianMark(size: 38, simplified: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Waiting for the next job', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(
                            'Offers ring and open full screen.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : onEnd,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End shift'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(5)),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.detail});
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final numeric = value.contains(RegExp(r'\d'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: (numeric ? mono(theme.textTheme.titleMedium) : theme.textTheme.titleMedium!).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (detail != null) Text(detail!, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

class UploadBanner extends StatelessWidget {
  const UploadBanner({super.key, required this.status, required this.peak});
  final TrackerStatus status;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = status.link == LinkState.online;
    final done = peak - status.queued;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                online ? 'Uploading your saved route… $done of $peak' : '${status.queued} location updates saved on this phone',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: online ? done / peak : null,
            minHeight: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

// --- Incoming offer -------------------------------------------------------------

/// A job offer, full screen: a countdown ring, how far, the stops, Accept.
class OfferView extends StatefulWidget {
  const OfferView({super.key, required this.job, required this.busy, required this.onAccept, required this.onDecline});
  final DriverJob job;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<OfferView> createState() => _OfferViewState();
}

class _OfferViewState extends State<OfferView> {
  late final Timer _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  static const _window = 30.0;

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final left = job.offerExpiresAt == null
        ? 0.0
        : math.max(0, job.offerExpiresAt!.difference(DateTime.now()).inMilliseconds / 1000).toDouble();
    final toPickup = job.toPickup;
    final toDropoff = job.toDropoff;
    final away = toPickup != null
        ? '${minutes(toPickup.durationS)} away'
        : (job.etaSeconds != null ? '${minutes(job.etaSeconds!.toDouble())} away' : 'Nearby');
    final legs = [
      if (toPickup != null) '${km(toPickup.distanceM)} to pickup',
      if (toDropoff != null) 'then ${km(toDropoff.distanceM)}',
    ].join(' · ');
    const fg = Color(0xFFF3F6FA);
    const muted = Color(0xFF9AA6B8);

    return Theme(
      data: buildTheme(Brightness.dark),
      child: Material(
        color: nightInk,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: job.urgent ? const Color(0xFF3B1D22) : const Color(0xFF172238),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        job.urgent ? 'URGENT JOB' : 'NEW JOB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: job.urgent ? const Color(0xFFFCA5A5) : const Color(0xFF7AA7FF),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '#${job.number}',
                      style: const TextStyle(fontFamily: monoFamily, fontSize: 15, color: muted),
                    ),
                  ],
                ),
                const Spacer(),
                Center(
                  child: SizedBox.square(
                    dimension: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: (left / _window).clamp(0, 1),
                            strokeWidth: 12,
                            strokeCap: StrokeCap.round,
                            color: liveAmber,
                            backgroundColor: const Color(0xFF1C2840),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${left.ceil()}',
                              style: const TextStyle(
                                fontFamily: monoFamily,
                                fontSize: 60,
                                fontWeight: FontWeight.w600,
                                color: fg,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('seconds to respond', style: TextStyle(fontSize: 13, color: muted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  away,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: fg),
                ),
                if (legs.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    legs,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: muted),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131C2E),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF263247)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StopLine(pickup: true, label: 'Pickup', text: placeText(job.pickupAddress, job.pickup)),
                      if (job.dropoff != null) ...[
                        const SizedBox(height: 12),
                        StopLine(pickup: false, label: 'Drop-off', text: placeText(job.dropoffAddress, job.dropoff!)),
                      ],
                      if ((job.notes ?? '').isNotEmpty) ...[
                        const Divider(height: 24, color: Color(0xFF263247)),
                        Text(job.notes!, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFFC9D1DC))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: widget.busy ? null : widget.onDecline,
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          textStyle: const TextStyle(fontFamily: 'Geist', fontSize: 19, fontWeight: FontWeight.w600),
                        ),
                        onPressed: widget.busy
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                widget.onAccept();
                              },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String placeText(String? address, LatLon p) =>
    (address ?? '').isNotEmpty ? address! : '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';

class StopLine extends StatelessWidget {
  const StopLine({super.key, required this.pickup, required this.label, required this.text, this.done = false});
  final bool pickup;
  final String label;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: pickup
              ? Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: done ? theme.colorScheme.outline : liveGreen, shape: BoxShape.circle),
                )
              : Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: dropoffPurple, width: 3),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(
                text,
                style: theme.textTheme.titleMedium?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- On a job -------------------------------------------------------------------

/// Working a job: the route on the map, the stops, and the next step.
class NavigateView extends StatelessWidget {
  const NavigateView({super.key, required this.job, required this.status, required this.busy, required this.onAdvance});
  final DriverJob job;
  final TrackerStatus status;
  final bool busy;
  final void Function(String status) onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, next, nextLabel) = switch (job.status) {
      'EN_ROUTE_PICKUP' || 'ASSIGNED' => ('Heading to pickup', 'ON_SITE', 'I\'ve arrived'),
      'ON_SITE' when job.dropoff != null => ('At pickup', 'EN_ROUTE_DROPOFF', 'Start trip to drop-off'),
      'ON_SITE' => ('At pickup', 'COMPLETED', 'Complete job'),
      'EN_ROUTE_DROPOFF' => ('Heading to drop-off', 'COMPLETED', 'Complete job'),
      _ => ('Job', null, null),
    };
    final toDropoff = job.status == 'EN_ROUTE_DROPOFF' || job.status == 'ON_SITE';
    final leg = toDropoff ? job.toDropoff : job.toPickup;
    final me = status.lat != null && status.lon != null ? LatLon(status.lat!, status.lon!) : null;
    final eta = leg == null ? null : DateTime.now().add(Duration(seconds: leg.durationS.round()));

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RadianMap(
                  me: me,
                  fit: true,
                  lines: [
                    if (job.toPickup != null && !toDropoff) MapLine(job.toPickup!.points, radianBlue),
                    if (job.toDropoff != null)
                      MapLine(
                        job.toDropoff!.points,
                        toDropoff ? radianBlue : dropoffPurple.withValues(alpha: 0.7),
                        width: toDropoff ? 6 : 4,
                      ),
                  ],
                  pickup: toDropoff ? null : job.pickup,
                  dropoff: job.dropoff,
                  padding: const EdgeInsets.only(top: 130),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: nightInk,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: radianBlue, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.north_east_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  leg == null ? title : minutes(leg.durationS),
                                  style: const TextStyle(
                                    fontFamily: monoFamily,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF3F6FA),
                                  ),
                                ),
                                Text(
                                  leg == null
                                      ? (toDropoff ? 'to drop-off' : 'to pickup')
                                      : '${km(leg.distanceM)} to ${toDropoff ? 'drop-off' : 'pickup'} · ETA ${clockTime(eta)}',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF9AA6B8)),
                                ),
                              ],
                            ),
                          ),
                          if (job.status != 'ON_SITE')
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF172238),
                                foregroundColor: const Color(0xFFF3F6FA),
                                minimumSize: const Size(0, 44),
                              ),
                              onPressed: () => openInMaps(context, job.destination),
                              child: const Text('Open in Maps'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -6))],
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('#${job.number}', style: mono(theme.textTheme.labelLarge).copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: radianBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.brightness == Brightness.dark ? signalBlue : radianBlue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (job.urgent)
                    const Text(
                      'Urgent',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: failRed),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              StopLine(
                pickup: true,
                label: toDropoff ? 'Pickup · done' : 'Pickup · now',
                text: placeText(job.pickupAddress, job.pickup),
                done: job.status == 'EN_ROUTE_DROPOFF',
              ),
              if (job.dropoff != null) ...[
                const SizedBox(height: 12),
                StopLine(
                  pickup: false,
                  label: toDropoff ? 'Drop-off · now' : 'Drop-off · next',
                  text: placeText(job.dropoffAddress, job.dropoff!),
                ),
              ],
              if ((job.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(job.notes!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              if (next != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: busy
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          onAdvance(next);
                        },
                  child: Text(nextLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Hands navigation to the driver's map app of choice.
Future<void> openInMaps(BuildContext context, LatLon to) async {
  final options = <(String, Uri)>[
    ('Google Maps', Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lon}&travelmode=driving')),
    ('Waze', Uri.parse('https://waze.com/ul?ll=${to.lat},${to.lon}&navigate=yes')),
    if (Platform.isIOS) ('Apple Maps', Uri.parse('https://maps.apple.com/?daddr=${to.lat},${to.lon}&dirflg=d')),
  ];
  final choice = await showModalBottomSheet<Uri>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (name, uri) in options)
            ListTile(leading: const Icon(Icons.directions_car), title: Text(name), onTap: () => Navigator.pop(ctx, uri)),
        ],
      ),
    ),
  );
  if (choice != null) await launchUrl(choice, mode: LaunchMode.externalApplication);
}
