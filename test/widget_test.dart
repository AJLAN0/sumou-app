// Basic smoke test for the Sumou app shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  testWidgets('Unauthenticated boot shows splash, then the entry screen in RTL',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SumouApp()));

    // Splash is shown first.
    await tester.pump();
    expect(find.text('سمو الإبداع'), findsOneWidget);

    // After the splash delay it routes to the entry screen.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('دخول سمو'), findsOneWidget);
    expect(find.text('تتبع مشروع'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('دخول سمو'))),
      TextDirection.rtl,
    );
  });
}
