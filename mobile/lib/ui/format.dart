// Small formatters shared by the driver app's screens.

String ago(DateTime? t) {
  if (t == null) return '—';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  return '${s ~/ 3600}h ago';
}

String sinceText(DateTime? since) => since == null ? '—' : durationText(DateTime.now().difference(since));

String durationText(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
}

String clockTime(DateTime? t) => t == null ? '—' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String km(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String minutes(double s) => s < 60 ? '<1 min' : '${(s / 60).round()} min';

String vehicleKind(String k) => switch (k) {
      'MOTORBIKE' => 'Motorbike',
      'AMBULANCE' => 'Ambulance',
      'VAN' => 'Van',
      'TRUCK' => 'Truck',
      _ => 'Car',
    };

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", or "Tuesday 27 Oct".
String dayText(DateTime t) {
  final now = DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}
