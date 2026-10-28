import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radian_driver/ui/login_screen.dart';

void main() {
  test('phone numbers are normalised to the local format', () {
    expect(localPhone('0240000001'), '0240000001');
    expect(localPhone('24 000 0001'), '0240000001');
    expect(localPhone('+233 24 000 0001'), '0240000001');
    expect(localPhone('233240000001'), '0240000001');
  });

  testWidgets('typing survives the keyboard compacting the header', (t) async {
    await t.pumpWidget(MaterialApp(home: LoginScreen(onSignedIn: (_) {})));
    expect(find.text('Ready to drive?'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0240000001');
    // The keyboard opens: the header shrinks so Sign in stays on screen.
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.reset);
    await t.pumpAndSettle();

    expect(find.text('Ready to drive?'), findsNothing);
    expect(find.text('0240000001'), findsOneWidget);
    final field = t.widget<EditableText>(find.descendant(of: find.widgetWithText(TextFormField, 'Phone number'), matching: find.byType(EditableText)));
    expect(field.focusNode.hasFocus, isTrue, reason: 'the field must keep focus while the layout changes');
  });
}
