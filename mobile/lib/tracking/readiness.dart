import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';

enum CheckState { ok, warn, fail }

enum CheckAction { enableLocation, grantLocation, openAppSettings, grantNotifications, allowBackground, phoneSetup }

/// One line of the pre-shift checklist.
class ReadinessItem {
  const ReadinessItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.state,
    this.action,
    this.actionLabel,
  });

  final String id;
  final String title;
  final String detail;
  final CheckState state;
  final CheckAction? action;
  final String? actionLabel;
}

class ReadinessReport {
  const ReadinessReport(this.items);
  final List<ReadinessItem> items;

  /// Location must work; everything else is advice.
  bool get canStart => items.every((i) => i.state != CheckState.fail);
  int get warnings => items.where((i) => i.state == CheckState.warn).length;
}

/// Phone makers whose battery managers kill background apps even with a
/// foreground service; drivers need to whitelist the app by hand.
/// See https://dontkillmyapp.com
const _aggressiveOems = {
  'xiaomi', 'redmi', 'poco', 'tecno', 'infinix', 'itel', 'oppo', 'realme',
  'oneplus', 'vivo', 'huawei', 'honor', 'samsung', 'meizu', 'asus', 'nokia',
};

class Readiness {
  static const _storage = FlutterSecureStorage();
  static const _oemDoneKey = 'radian.oem_setup_done';

  static Future<ReadinessReport> check() async {
    final items = <ReadinessItem>[];

    // Location services and permission: required.
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    items.add(servicesOn
        ? const ReadinessItem(id: 'gps', title: 'Location is on', detail: 'GPS is available.', state: CheckState.ok)
        : const ReadinessItem(
            id: 'gps',
            title: 'Location is off',
            detail: 'Turn on location so dispatch can see your vehicle.',
            state: CheckState.fail,
            action: CheckAction.enableLocation,
            actionLabel: 'Turn on',
          ));

    final perm = await Geolocator.checkPermission();
    items.add(switch (perm) {
      LocationPermission.always || LocationPermission.whileInUse => const ReadinessItem(
          id: 'perm', title: 'Location access allowed', detail: 'Radian can use GPS during your shift.', state: CheckState.ok),
      LocationPermission.deniedForever => const ReadinessItem(
          id: 'perm',
          title: 'Location access blocked',
          detail: 'Allow location for Radian in Settings.',
          state: CheckState.fail,
          action: CheckAction.openAppSettings,
          actionLabel: 'Settings',
        ),
      _ => const ReadinessItem(
          id: 'perm',
          title: 'Location access needed',
          detail: 'Radian uses your location only while you are on shift.',
          state: CheckState.fail,
          action: CheckAction.grantLocation,
          actionLabel: 'Allow',
        ),
    });

    if (Platform.isAndroid) {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        items.add(const ReadinessItem(
          id: 'notif',
          title: 'Notifications off',
          detail: 'Without them Android may stop tracking in the background.',
          state: CheckState.warn,
          action: CheckAction.grantNotifications,
          actionLabel: 'Allow',
        ));
      }

      final battery = await Permission.ignoreBatteryOptimizations.status;
      items.add(battery.isGranted
          ? const ReadinessItem(
              id: 'bg', title: 'Background tracking allowed', detail: 'Battery saver won\'t pause tracking.', state: CheckState.ok)
          : const ReadinessItem(
              id: 'bg',
              title: 'Battery saver may pause tracking',
              detail: 'Allow Radian to run in the background during shifts.',
              state: CheckState.warn,
              action: CheckAction.allowBackground,
              actionLabel: 'Allow',
            ));

      final maker = await manufacturer();
      if (_aggressiveOems.contains(maker) && await _storage.read(key: _oemDoneKey) == null) {
        items.add(ReadinessItem(
          id: 'oem',
          title: '${_brand(maker)} phone setup',
          detail: 'One-time step so your phone doesn\'t close Radian.',
          state: CheckState.warn,
          action: CheckAction.phoneSetup,
          actionLabel: 'Show me',
        ));
      }
    }

    items.add(await _server());
    final battery = await _battery();
    if (battery != null) items.add(battery);
    return ReadinessReport(items);
  }

  static Future<ReadinessItem> _server() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiUrl}/healthz')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return const ReadinessItem(id: 'server', title: 'Connected to dispatch', detail: 'Your updates will arrive live.', state: CheckState.ok);
      }
    } catch (_) {}
    return const ReadinessItem(
      id: 'server',
      title: 'Can\'t reach dispatch',
      detail: 'You can still start. Your route is saved and uploads when you\'re back online.',
      state: CheckState.warn,
    );
  }

  /// Null when the level is unknown (e.g. simulators): nothing useful to say.
  static Future<ReadinessItem?> _battery() async {
    try {
      final b = Battery();
      final level = await b.batteryLevel;
      final charging = await b.batteryState == BatteryState.charging;
      if (level < 0) throw StateError('unknown');
      if (level < 20 && !charging) {
        return ReadinessItem(
          id: 'battery',
          title: 'Battery low ($level%)',
          detail: 'Plug in if you can. Tracking uses more power on long shifts.',
          state: CheckState.warn,
        );
      }
      return ReadinessItem(
        id: 'battery',
        title: 'Battery $level%${charging ? ' · charging' : ''}',
        detail: 'Enough for your shift.',
        state: CheckState.ok,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> manufacturer() async {
    if (!Platform.isAndroid) return 'apple';
    final info = await DeviceInfoPlugin().androidInfo;
    return info.manufacturer.toLowerCase();
  }

  static Future<void> markPhoneSetupDone() => _storage.write(key: _oemDoneKey, value: '1');

  static String _brand(String m) => m.isEmpty ? 'Phone' : m[0].toUpperCase() + m.substring(1);

  /// Step-by-step instructions for the phone's battery manager.
  static List<String> phoneSetupSteps(String maker) => switch (maker) {
        'tecno' || 'infinix' || 'itel' => [
            'Open Phone Master (or Settings › Apps).',
            'Find Auto-start management and turn Radian on.',
            'In Settings › Battery › App launch (or Power saving), set Radian to Manage manually and allow all three options.',
            'Lock Radian in recent apps: open the recent apps view, pull Radian down or tap the lock icon.',
          ],
        'xiaomi' || 'redmi' || 'poco' => [
            'Settings › Apps › Manage apps › Radian.',
            'Turn on Autostart.',
            'Battery saver › No restrictions.',
            'Lock Radian in recent apps (long-press its card › lock).',
          ],
        'samsung' => [
            'Settings › Battery › Background usage limits.',
            'Make sure Radian is not in Sleeping or Deep sleeping apps.',
            'Add Radian to Never sleeping apps.',
          ],
        'huawei' || 'honor' => [
            'Settings › Battery › App launch.',
            'Turn off Manage automatically for Radian.',
            'Turn on Auto-launch, Secondary launch and Run in background.',
          ],
        'oppo' || 'realme' || 'oneplus' || 'vivo' => [
            'Settings › Battery › Background power consumption (or App battery management).',
            'Set Radian to Allow background activity / Don\'t optimise.',
            'Settings › Apps › Auto launch: turn on Radian.',
          ],
        _ => [
            'Settings › Apps › Radian › Battery.',
            'Choose Unrestricted (or Don\'t optimise).',
          ],
      };
}
