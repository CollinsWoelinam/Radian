// End-to-end dispatch: a driver on shift receives a job created by the
// dispatcher, accepts it and works it through to completion. Needs the full
// backend (api with dispatch, ingest, persister) and no other online vehicles
// closer to the pickup than this driver (stop the simulator).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:radian_driver/auth/session.dart';
import 'package:radian_driver/config.dart';
import 'package:radian_driver/main.dart' as app;

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  // Let tool/tour.sh capture what the screen showed when we gave up.
  // ignore: avoid_print
  print('TOUR:timeout');
  await t.pump(const Duration(seconds: 2));
  throw TestFailure('Timed out waiting for $f');
}

Future<void> hold(WidgetTester t, String screen) async {
  await t.pump(const Duration(milliseconds: 800));
  // ignore: avoid_print
  print('TOUR:$screen');
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

/// Creates a job as the demo dispatcher, a few hundred metres from (lat, lon).
Future<void> createJobNear(double lat, double lon) async {
  final login = await http.post(Uri.parse('${AppConfig.apiUrl}/v1/auth/dispatcher/login'),
      body: jsonEncode({'email': 'dispatch@radian.dev', 'password': 'radian-demo'}));
  final token = (jsonDecode(login.body) as Map<String, dynamic>)['token'] as String;
  final res = await http.post(
    Uri.parse('${AppConfig.apiUrl}/v1/jobs'),
    headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'pickup': {'lat': lat + 0.003, 'lon': lon},
      'pickup_address': 'Accra Mall, main entrance',
      'dropoff': {'lat': lat + 0.012, 'lon': lon + 0.006},
      'dropoff_address': 'Tetteh Quarshie Interchange',
      'priority': 1,
      'notes': 'Two boxes, fragile',
    }),
  );
  expect(res.statusCode, 201, reason: res.body);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('driver accepts a dispatched job and completes it', (t) async {
    await SessionStore.clear();
    await ShiftStore.end();
    app.main();
    await pumpUntil(t, find.text('Sign in'));
    await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0240000001');
    await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'radian-demo');
    TextInput.finishAutofillContext(shouldSave: false);
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await pumpUntil(t, find.text('Start shift'));

    await t.tap(find.text('Start shift'));
    await pumpUntil(t, find.textContaining(RegExp(r'^[1-9]\d* delivered$')), timeout: const Duration(seconds: 90));
    // Let the persister record our position so dispatch can find us.
    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    // Put the job next to wherever this device actually is.
    final here = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition();
    await createJobNear(here.latitude, here.longitude);

    await pumpUntil(t, find.text('Accept'), timeout: const Duration(seconds: 80));
    await hold(t, '10-job-offer');
    await t.tap(find.text('Accept'));

    await pumpUntil(t, find.text('I\'ve arrived'));
    await hold(t, '11-job-to-pickup');
    await t.tap(find.text('I\'ve arrived'));

    await pumpUntil(t, find.text('Start trip to drop-off'));
    await hold(t, '12-job-at-pickup');
    await t.tap(find.text('Start trip to drop-off'));

    await pumpUntil(t, find.text('Complete job'));
    await hold(t, '13-job-to-dropoff');
    await t.tap(find.text('Complete job'));
    await pumpUntil(t, find.text('Job complete. Nice work.'));
    await hold(t, '14-job-complete');

    await t.tap(find.text('End shift'));
    await pumpUntil(t, find.text('End shift?'));
    await t.tap(find.widgetWithText(FilledButton, 'End shift').last);
    await pumpUntil(t, find.text('Off shift'));
  });
}
