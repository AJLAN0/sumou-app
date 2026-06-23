// Basic smoke test for the Sumou app shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  testWidgets('App boots in RTL with Sumou branding', (tester) async {
    await tester.pumpWidget(const SumouApp());
    await tester.pumpAndSettle();

    // The component preview (current dev home) renders its title.
    expect(find.text('مكوّنات سمو'), findsOneWidget);

    // The interface is right-to-left.
    expect(Directionality.of(tester.element(find.text('مكوّنات سمو'))),
        TextDirection.rtl);
  });
}
