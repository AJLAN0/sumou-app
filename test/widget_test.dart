// Basic smoke test for the Sumou app shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  testWidgets('App boots in RTL on the entry screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SumouApp()));
    await tester.pumpAndSettle();

    // Unauthenticated boot redirects to the (placeholder) entry screen, which
    // renders its title in both the app bar and the body.
    expect(find.text('الدخول'), findsWidgets);

    // The interface is right-to-left.
    expect(
      Directionality.of(tester.element(find.text('الدخول').first)),
      TextDirection.rtl,
    );
  });
}
