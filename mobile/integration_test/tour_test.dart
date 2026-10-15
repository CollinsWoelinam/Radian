// Screen tour for visual review: walks through every screen and prints
// "TOUR:<name>" when each is settled, so tool/tour.sh can screenshot it.
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
  throw TestFailure('Timed out waiting for $f');
}

Future<void> hold(WidgetTester t, String screen) async {
  await t.pump(const Duration(milliseconds: 800));
  // ignore: avoid_print
  print('TOUR:$screen');
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (t) async {
    await SessionStore.clear();
    await ShiftStore.end(); // don't auto-resume a shift from a previous run
    app.main();
    await pumpUntil(t, find.text('Sign in'));
    await hold(t, '01-login');

    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await t.pump(const Duration(milliseconds: 300));
    await hold(t, '02-login-validation');

    await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0240000001');
    await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await pumpUntil(t, find.textContaining('incorrect'));
    FocusManager.instance.primaryFocus?.unfocus();
    await hold(t, '03-login-error');

    // Re-focus before typing: after the keyboard was dismissed, enterText
    // alone doesn't reattach to the field.
    final password = find.widgetWithText(TextFormField, 'Password');
    await t.tap(password);
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(password, 'radian-demo');
    await t.pump(const Duration(milliseconds: 300));
    // Skip the OS "Save password?" sheet: it's native, so the test can't
    // dismiss it, and it would cover every screen after sign-in.
    TextInput.finishAutofillContext(shouldSave: false);
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await pumpUntil(t, find.text('Start shift'));
    await hold(t, '04-off-shift');

    await t.tap(find.text('Start shift'));
    await pumpUntil(t, find.text('On shift · Live'));
    await pumpUntil(t, find.textContaining(RegExp(r'^[1-9]\d* delivered$')));
    await hold(t, '05-on-shift-live');
    await hold(t, '06-on-shift-driving');

    await t.tap(find.byTooltip('More'));
    await t.pump(const Duration(milliseconds: 500));
    await hold(t, '07-menu-on-shift');
    await t.tapAt(const Offset(10, 400)); // dismiss
    await t.pump(const Duration(milliseconds: 500));

    await t.tap(find.text('End shift'));
    await pumpUntil(t, find.text('End shift?'));
    await hold(t, '08-end-confirm');
    await t.tap(find.widgetWithText(FilledButton, 'End shift').last);
    await pumpUntil(t, find.text('Off shift'));
    await hold(t, '09-shift-ended');
  });
}
