import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_auth_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_project_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_tracking_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_user_repository.dart';
import 'package:sumou_app/data/repositories/project_repository.dart';
import 'package:sumou_app/data/repositories/tracking_repository.dart';

/// Overrides that keep tests/previews on the in-memory mock auth.
///
/// The normal app wires [authRepositoryProvider] to the real
/// `SupabaseAuthRepository`, which needs an initialized Supabase client. Tests
/// must explicitly opt into the mock — it is never selected implicitly. A fresh
/// [MockAuthRepository] is created per call so tests don't share session state.
List<Override> mockAuthOverrides() => [
  authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
  userRepositoryProvider.overrideWith((ref) => MockUserRepository()),
];

/// Explicit deterministic project/tracking overrides for tests and previews.
/// The production providers never inspect build mode or test state.
List<Override> mockProjectTrackingOverrides({
  ProjectRepository? projectRepository,
  TrackingRepository? trackingRepository,
}) => [
  projectRepositoryProvider.overrideWithValue(
    projectRepository ?? MockProjectRepository(),
  ),
  trackingRepositoryProvider.overrideWithValue(
    trackingRepository ?? MockTrackingRepository(),
  ),
];

List<Override> mockAppOverrides({
  ProjectRepository? projectRepository,
  TrackingRepository? trackingRepository,
}) => [
  ...mockAuthOverrides(),
  ...mockProjectTrackingOverrides(
    projectRepository: projectRepository,
    trackingRepository: trackingRepository,
  ),
];

/// A [ProviderContainer] pinned to the mock auth repository (plus any [extra]
/// overrides). Prefer this over a bare `ProviderContainer()` in widget tests.
ProviderContainer makeMockContainer({
  List<Override> extra = const [],
  ProjectRepository? projectRepository,
  TrackingRepository? trackingRepository,
}) => ProviderContainer(
  overrides: [
    ...mockAppOverrides(
      projectRepository: projectRepository,
      trackingRepository: trackingRepository,
    ),
    ...extra,
  ],
);

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
