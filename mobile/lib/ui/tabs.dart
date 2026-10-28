import 'package:flutter/material.dart';

import '../auth/session.dart';
import '../jobs/driver_job.dart';
import '../shifts/shift_api.dart';
import 'format.dart';
import 'map_view.dart';
import 'shift_views.dart';
import 'theme.dart';

// --- Shift summary ---------------------------------------------------------------

/// A finished (or past) shift: its route, numbers and jobs.
class ShiftSummaryScreen extends StatelessWidget {
  const ShiftSummaryScreen({super.key, required this.detail, this.justEnded = false});

  final ShiftDetail detail;
  final bool justEnded;

  /// Opens a past shift, loading its detail first.
  static Future<void> open(BuildContext context, String shiftId) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final d = await ShiftApi.get(shiftId);
      await nav.push(MaterialPageRoute<void>(builder: (_) => ShiftSummaryScreen(detail: d)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t load that shift. Check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = detail.shift;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), children: [
              Row(children: [
                const RadianMark(size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(justEnded ? 'Shift complete' : dayText(s.startedAt), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4)),
                    Text('${dayText(s.startedAt)} · ${clockTime(s.startedAt)} – ${clockTime(s.endedAt)}', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 190,
                  child: detail.route.length > 1
                      ? RadianMap(fit: true, interactive: false, lines: [MapLine(detail.route, signalBlue, width: 4)], me: detail.route.last)
                      : Container(color: theme.colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: Text('No route recorded', style: TextStyle(color: muted))),
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  StatTile(label: 'On shift', value: durationText(s.duration)),
                  StatTile(label: 'Driven', value: km(detail.distanceM)),
                  StatTile(label: 'Jobs', value: '${detail.jobs.length}'),
                  StatTile(label: 'Driving time', value: durationText(Duration(seconds: detail.drivingS))),
                ],
              ),
              if (detail.jobs.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Jobs', style: theme.textTheme.titleSmall?.copyWith(color: muted)),
                const SizedBox(height: 6),
                Card(
                  child: Column(children: [
                    for (final (i, j) in detail.jobs.indexed) ...[
                      if (i > 0) Divider(height: 1, color: theme.dividerColor),
                      ListTile(
                        leading: Text('#${j.number}', style: mono(theme.textTheme.bodyMedium).copyWith(color: muted)),
                        title: Text(j.dropoffAddress.isEmpty ? j.pickupAddress : '${j.pickupAddress} → ${j.dropoffAddress}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(clockTime(j.completedAt), style: mono(theme.textTheme.bodyMedium)),
                      ),
                    ],
                  ]),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ),
        ]),
      ),
    );
  }
}

// --- Jobs -----------------------------------------------------------------------

/// The current job, and what was completed this shift.
class JobsTab extends StatelessWidget {
  const JobsTab({super.key, required this.job, required this.onShift, required this.today, required this.onShowJob, required this.onRefresh});

  final DriverJob? job;
  final bool onShift;
  final ShiftDetail? today;
  final VoidCallback onShowJob;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final done = today?.jobs ?? const <ShiftJob>[];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
          Text('Jobs', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (job != null)
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onShowJob,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('#${job!.number}', style: mono(theme.textTheme.labelLarge).copyWith(color: muted)),
                      const SizedBox(width: 8),
                      Text(job!.isOffer ? 'Offer waiting' : 'In progress', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Icon(Icons.chevron_right, color: muted),
                    ]),
                    const SizedBox(height: 10),
                    StopLine(pickup: true, label: 'Pickup', text: placeText(job!.pickupAddress, job!.pickup)),
                    if (job!.dropoff != null) ...[const SizedBox(height: 8), StopLine(pickup: false, label: 'Drop-off', text: placeText(job!.dropoffAddress, job!.dropoff!))],
                  ]),
                ),
              ),
            )
          else
            _Empty(icon: Icons.inbox_outlined, text: onShift ? 'No job right now. Offers ring and open full screen.' : 'Start a shift to receive jobs.'),
          const SizedBox(height: 18),
          Text(onShift ? 'Done this shift' : 'Last shift', style: theme.textTheme.titleSmall?.copyWith(color: muted)),
          const SizedBox(height: 6),
          if (done.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('No completed jobs yet.', style: TextStyle(color: muted)))
          else
            Card(
              child: Column(children: [
                for (final (i, j) in done.indexed) ...[
                  if (i > 0) Divider(height: 1, color: theme.dividerColor),
                  ListTile(
                    leading: Text('#${j.number}', style: mono(theme.textTheme.bodyMedium).copyWith(color: muted)),
                    title: Text(j.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: j.dropoffAddress.isEmpty ? null : Text('→ ${j.dropoffAddress}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(clockTime(j.completedAt), style: mono(theme.textTheme.bodyMedium)),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

// --- History ----------------------------------------------------------------------

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.refreshKey});

  /// Changes when a shift starts or ends, to reload the list.
  final int refreshKey;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<ShiftSummary>? _shifts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryTab old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    try {
      final s = await ShiftApi.list();
      if (mounted) {
        setState(() {
          _shifts = s;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t load your shifts. Pull to retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final shifts = _shifts;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
          Text('History', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (_error != null) _Empty(icon: Icons.cloud_off_outlined, text: _error!),
          if (shifts == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (shifts != null && shifts.isEmpty) const _Empty(icon: Icons.history, text: 'Your shifts will appear here.'),
          if (shifts != null && shifts.isNotEmpty)
            Card(
              child: Column(children: [
                for (final (i, s) in shifts.indexed) ...[
                  if (i > 0) Divider(height: 1, color: theme.dividerColor),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(dayText(s.startedAt), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(s.endedAt == null ? 'On shift since ${clockTime(s.startedAt)}' : '${clockTime(s.startedAt)} – ${clockTime(s.endedAt)} · ${durationText(s.duration)}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(s.distanceM == null ? '—' : km(s.distanceM!), style: mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                      Text(s.jobsCompleted == null ? '' : '${s.jobsCompleted} jobs', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    ]),
                    onTap: () => ShiftSummaryScreen.open(context, s.id),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

// --- Profile ----------------------------------------------------------------------

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.session, required this.onShift, required this.onSignOut, required this.onPhoneSetup});

  final Session session;
  final bool onShift;
  final VoidCallback onSignOut;
  final VoidCallback onPhoneSetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final initials = session.driverName.split(RegExp(r'\s+')).map((w) => w.isEmpty ? '' : w[0]).take(2).join().toUpperCase();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
        Text('Profile', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        Row(children: [
          CircleAvatar(radius: 30, backgroundColor: radianBlue, child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.driverName, style: theme.textTheme.titleLarge),
              Text('Driver', style: TextStyle(color: muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(session.plate, style: mono(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(vehicleKind(session.vehicleKind)),
            ),
            Divider(height: 1, color: theme.dividerColor),
            ListTile(
              leading: const Icon(Icons.phonelink_setup_outlined),
              title: const Text('Phone setup'),
              subtitle: const Text('Keep tracking running in the background'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onPhoneSetup,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: onShift ? muted : failRed),
            title: Text('Sign out', style: TextStyle(color: onShift ? muted : failRed, fontWeight: FontWeight.w600)),
            subtitle: onShift ? const Text('End your shift first') : null,
            enabled: !onShift,
            onTap: onSignOut,
          ),
        ),
        const SizedBox(height: 24),
        Center(child: Text('Radian Driver', style: theme.textTheme.bodySmall?.copyWith(color: muted))),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).dividerColor)),
      child: Row(children: [
        Icon(icon, color: muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: muted))),
      ]),
    );
  }
}
