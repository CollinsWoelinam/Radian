// End-to-end: sign in against the dev backend, start a shift, and wait for
// the server to acknowledge GPS points. Needs the backend running (make up,
// ingest, persister, api, seed) and the device's location simulated.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:radian_driver/auth/session.dart';
import 'package:radian_driver/main.dart' as app;

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('driver signs in, goes live, and points are delivered', (t) async {
    await SessionStore.clear();
    app.main();
    await pumpUntil(t, find.text('Sign in'));

    await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0240000001');
    await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'radian-demo');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await pumpUntil(t, find.text('Start shift'));
    expect(find.text('GR 1024-26'), findsOneWidget);

    await t.tap(find.text('Start shift'));
    await pumpUntil(t, find.text('On shift · Live'));
    await pumpUntil(t, find.textContaining(RegExp(r'^[1-9]\d* delivered$')), timeout: const Duration(seconds: 90));

    await t.pump(const Duration(seconds: 30)); // keep driving for a while
    await t.tap(find.text('End shift'));
    await pumpUntil(t, find.text('Off shift'));
  });
}
