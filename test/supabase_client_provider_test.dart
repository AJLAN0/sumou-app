import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Declared under dev_dependencies; mocks local storage so Supabase.initialize
// can run offline in a unit test.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sumou_app/core/providers/supabase_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('supabaseClientProvider is injectable (override wins)', () {
    // A constructed client makes no network call; this asserts the DI contract
    // without touching Supabase.instance.
    final fake = SupabaseClient('https://fake.supabase.co', 'fake-anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    expect(container.read(supabaseClientProvider), same(fake));
  });

  test(
    'supabaseClientProvider returns the initialized canonical client',
    () async {
      SharedPreferences.setMockInitialValues({});
      // Fake but well-formed values — Supabase.initialize does no network call and
      // does not validate the key at init time. Never a real key.
      await Supabase.initialize(
        url: 'https://test-project.supabase.co',
        publishableKey: 'test-anon-key-not-real',
        debug: false,
      );
      addTearDown(() async => Supabase.instance.dispose());

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(supabaseClientProvider),
        same(Supabase.instance.client),
      );
    },
  );
}
