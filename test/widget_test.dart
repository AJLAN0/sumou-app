// Basic smoke test for the Sumou app shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  testWidgets('App boots in RTL with Sumou branding', (tester) async {
    await tester.pumpWidget(const SumouApp());
    await tester.pump();

    // Redirect sends the initial route to the (placeholder) entry screen.
    expect(find.text('الدخول'), findsOneWidget);

    // The interface is right-to-left.
    expect(
      Directionality.of(tester.element(find.text('الدخول'))),
      TextDirection.rtl,
    );
  });
}
