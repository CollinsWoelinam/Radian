import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radian_driver/ui/login_screen.dart';

void main() {
  testWidgets('typing survives the keyboard compacting the header', (t) async {
    await t.pumpWidget(MaterialApp(home: LoginScreen(onSignedIn: (_) {})));
    expect(find.text('Your shift, tracked and dispatched.'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0240000001');
    // The keyboard opens: the header shrinks so Sign in stays on screen.
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.reset);
    await t.pumpAndSettle();

    expect(find.text('Your shift, tracked and dispatched.'), findsNothing);
    expect(find.text('0240000001'), findsOneWidget);
    final field = t.widget<EditableText>(find.descendant(of: find.widgetWithText(TextFormField, 'Phone number'), matching: find.byType(EditableText)));
    expect(field.focusNode.hasFocus, isTrue, reason: 'the field must keep focus while the layout changes');
  });
}
