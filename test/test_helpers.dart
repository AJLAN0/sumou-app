import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_auth_repository.dart';

/// Overrides that keep tests/previews on the in-memory mock auth.
///
/// The normal app wires [authRepositoryProvider] to the real
/// `SupabaseAuthRepository`, which needs an initialized Supabase client. Tests
/// must explicitly opt into the mock — it is never selected implicitly. A fresh
/// [MockAuthRepository] is created per call so tests don't share session state.
List<Override> mockAuthOverrides() => [
  authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
];

/// A [ProviderContainer] pinned to the mock auth repository (plus any [extra]
/// overrides). Prefer this over a bare `ProviderContainer()` in widget tests.
ProviderContainer makeMockContainer({List<Override> extra = const []}) =>
    ProviderContainer(overrides: [...mockAuthOverrides(), ...extra]);

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
}) => scrollAndTapCardFinder(
  tester,
  find.text(text),
  scrollable: scrollable,
  scrollDelta: scrollDelta,
);
