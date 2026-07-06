import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scrolls [label] into view and taps the enclosing [InkWell] (e.g. SumouCard).
Future<void> scrollAndTapCardFinder(
  WidgetTester tester,
  Finder label, {
  Finder? scrollable,
  double scrollDelta = 300,
}) async {
  await tester.scrollUntilVisible(
    label,
    scrollDelta,
    scrollable: scrollable ?? find.byType(Scrollable).first,
  );
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(of: label, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

/// Scrolls [text] into view and taps the enclosing [InkWell] (e.g. SumouCard).
Future<void> scrollAndTapCard(
  WidgetTester tester,
  String text, {
  Finder? scrollable,
  double scrollDelta = 300,
}) =>
    scrollAndTapCardFinder(
      tester,
      find.text(text),
      scrollable: scrollable,
      scrollDelta: scrollDelta,
    );
