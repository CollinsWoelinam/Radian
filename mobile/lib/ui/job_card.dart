import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../jobs/driver_job.dart';
import 'theme.dart';

/// A job offer with a countdown, or the job in progress with the next step.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onAdvance,
  });

  final DriverJob job;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final void Function(String status) onAdvance;

  @override
  Widget build(BuildContext context) => job.isOffer ? _offer(context) : _active(context);

  Widget _offer(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: job.urgent ? failRed : theme.colorScheme.primary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.notifications_active, color: job.urgent ? failRed : theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${job.urgent ? 'Urgent job' : 'New job'} #${job.number}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (job.etaSeconds != null) Text('${(job.etaSeconds! / 60).ceil()} min away', style: theme.textTheme.labelLarge),
          ]),
          const SizedBox(height: 10),
          if (job.offerExpiresAt != null) _Countdown(expiresAt: job.offerExpiresAt!),
          const SizedBox(height: 12),
          _Stop(icon: Icons.trip_origin, color: liveGreen, label: 'Pickup', text: _place(job.pickupAddress, job.pickup)),
          if (job.dropoff != null)
            _Stop(icon: Icons.place, color: dropoffPurple, label: 'Drop-off', text: _place(job.dropoffAddress, job.dropoff!)),
          if ((job.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(job.notes!, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: busy ? null : onDecline,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        HapticFeedback.heavyImpact();
                        onAccept();
                      },
                child: const Text('Accept'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _active(BuildContext context) {
    final theme = Theme.of(context);
    final (title, next, nextLabel) = switch (job.status) {
      'EN_ROUTE_PICKUP' || 'ASSIGNED' => ('Head to pickup', 'ON_SITE', 'I\'ve arrived'),
      'ON_SITE' when job.dropoff != null => ('At pickup', 'EN_ROUTE_DROPOFF', 'Start trip to drop-off'),
      'ON_SITE' => ('At pickup', 'COMPLETED', 'Complete job'),
      'EN_ROUTE_DROPOFF' => ('Head to drop-off', 'COMPLETED', 'Complete job'),
      _ => ('Job', null, null),
    };
    final toDropoff = job.status == 'EN_ROUTE_DROPOFF' || job.status == 'ON_SITE' && job.dropoff != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('#${job.number}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (job.urgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: failRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: const Text('URGENT', style: TextStyle(color: failRed, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 12),
          _Stop(
            icon: Icons.trip_origin,
            color: liveGreen,
            label: 'Pickup',
            text: _place(job.pickupAddress, job.pickup),
            done: toDropoff,
          ),
          if (job.dropoff != null)
            _Stop(icon: Icons.place, color: dropoffPurple, label: 'Drop-off', text: _place(job.dropoffAddress, job.dropoff!)),
          if ((job.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(job.notes!, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 14),
          if (job.status != 'ON_SITE')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _navigate(context, job.destination),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(toDropoff ? 'Navigate to drop-off' : 'Navigate to pickup'),
            ),
          if (next != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      onAdvance(next);
                    },
              child: Text(nextLabel!),
            ),
          ],
        ]),
      ),
    );
  }
}

String _place(String? address, LatLon p) =>
    (address ?? '').isNotEmpty ? address! : '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';

/// Hands navigation to the driver's map app of choice.
Future<void> _navigate(BuildContext context, LatLon to) async {
  final options = <(String, Uri)>[
    ('Google Maps', Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lon}&travelmode=driving')),
    ('Waze', Uri.parse('https://waze.com/ul?ll=${to.lat},${to.lon}&navigate=yes')),
    if (Platform.isIOS) ('Apple Maps', Uri.parse('https://maps.apple.com/?daddr=${to.lat},${to.lon}&dirflg=d')),
  ];
  final choice = await showModalBottomSheet<Uri>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (name, uri) in options)
          ListTile(leading: const Icon(Icons.directions_car), title: Text(name), onTap: () => Navigator.pop(ctx, uri)),
      ]),
    ),
  );
  if (choice != null) await launchUrl(choice, mode: LaunchMode.externalApplication);
}

class _Stop extends StatelessWidget {
  const _Stop({required this.icon, required this.color, required this.label, required this.text, this.done = false});

  final IconData icon;
  final Color color;
  final String label;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(done ? Icons.check_circle : icon, color: done ? theme.colorScheme.outline : color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  static const _window = 30.0;

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now()).inMilliseconds / 1000;
    final secs = left.clamp(0, _window);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: secs / _window,
          minHeight: 6,
          color: secs < 10 ? failRed : warnAmber,
        ),
      ),
      const SizedBox(height: 4),
      Text('${secs.ceil()}s to respond', style: Theme.of(context).textTheme.labelSmall),
    ]);
  }
}
