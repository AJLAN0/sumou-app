// Basic smoke test for the Sumou app shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  testWidgets('Unauthenticated boot redirects to the entry route in RTL',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SumouApp()));
    await tester.pumpAndSettle();

    // Redirect sends the initial route to the (placeholder) entry screen.
    expect(find.text('الدخول'), findsOneWidget);

    // The interface is right-to-left.
    expect(
      Directionality.of(tester.element(find.text('الدخول'))),
      TextDirection.rtl,
    );
  });
}
