import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

enum PermissionProblem { servicesOff, denied, deniedForever }

/// Everything a shift needs before tracking can start. While-in-use location
/// is enough on both platforms: Android's location foreground service and
/// iOS background location updates both run on it once started in the
/// foreground, so we never ask for "Allow all the time".
class TrackingPermissions {
  static Future<PermissionProblem?> ensure() async {
    if (!await Geolocator.isLocationServiceEnabled()) return PermissionProblem.servicesOff;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) return PermissionProblem.deniedForever;
    if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
      return PermissionProblem.denied;
    }

    if (Platform.isAndroid) {
      // Android 13+: the foreground-service notification needs this to show.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    return null;
  }

  static Future<void> openSettings(PermissionProblem p) =>
      p == PermissionProblem.servicesOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();
}
