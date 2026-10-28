// Real-device check that tracking survives the app going to the background
// and the screen turning off. tool/background_android.sh presses Home and
// turns the screen off when this test prints the matching markers, then
// counts how many points reached the server in each phase.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:radian_driver/auth/session.dart';
import 'package:radian_driver/main.dart' as app;

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 90)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  // ignore: avoid_print
  print('TOUR:timeout');
  throw TestFailure('Timed out waiting for $f');
}

// ignore: avoid_print
void mark(String m) => print('TOUR:$m');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tracking continues in the background and with the screen off', (t) async {
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
    await pumpUntil(t, find.textContaining(RegExp(r'^[1-9]\d* delivered$')));

    mark('bg-home'); // host presses Home
    await Future<void>.delayed(const Duration(seconds: 75));
    mark('bg-sleep'); // host turns the screen off
    await Future<void>.delayed(const Duration(seconds: 120));
    mark('bg-wake'); // host wakes the phone and brings the app back
    await Future<void>.delayed(const Duration(seconds: 10));

    await pumpUntil(t, find.text('End shift'));
    await t.tap(find.text('End shift'));
    await pumpUntil(t, find.text('End shift?'));
    await t.tap(find.widgetWithText(FilledButton, 'End shift').last);
    await pumpUntil(t, find.text('Shift complete'));
    await t.tap(find.text('Done'));
    await pumpUntil(t, find.text('Off shift'));
    mark('bg-done');
  });
}
