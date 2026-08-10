import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/providers/supabase_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_project_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_tracking_repository.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_project_repository.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_tracking_repository.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://fake.supabase.co', 'fake-publishable-key');
  });

  test('normal project provider resolves to SupabaseProjectRepository', () {
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(projectRepositoryProvider),
      isA<SupabaseProjectRepository>(),
    );
  });

  test('normal tracking provider resolves to SupabaseTrackingRepository', () {
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(trackingRepositoryProvider),
      isA<SupabaseTrackingRepository>(),
    );
  });

  test('project provider supports an explicit mock override', () {
    final mock = MockProjectRepository();
    final container = ProviderContainer(
      overrides: [projectRepositoryProvider.overrideWithValue(mock)],
    );
    addTearDown(container.dispose);

    expect(container.read(projectRepositoryProvider), same(mock));
  });

  test('tracking provider supports an explicit mock override', () {
    final mock = MockTrackingRepository();
    final container = ProviderContainer(
      overrides: [trackingRepositoryProvider.overrideWithValue(mock)],
    );
    addTearDown(container.dispose);

    expect(container.read(trackingRepositoryProvider), same(mock));
  });

  test('production providers contain no debug or test fallback', () {
    final source =
        File('lib/core/providers/repository_providers.dart').readAsStringSync();

    expect(source, contains('SupabaseProjectRepository'));
    expect(source, contains('SupabaseTrackingRepository'));
    expect(source, isNot(contains('kDebugMode')));
    expect(source, isNot(contains('assert(')));
    expect(source, isNot(contains('under test')));
    expect(source, isNot(contains('Platform.')));
  });
}
