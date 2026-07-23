import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import 'app.dart';

/// App bootstrap (Sprint 10 Step 10.4).
///
/// Reads the compile-time Supabase configuration, **fails fast** with a safe,
/// value-free error when it is incomplete/invalid, initializes Supabase exactly
/// once, then runs the existing [ProviderScope] / [SumouApp] root unchanged.
///
/// This step only *initializes* Supabase. It performs **no** sign-in, session
/// load, profile query, RPC, or Edge Function call — the app keeps using the
/// mock `authRepositoryProvider`. The `service_role` key is never used here.
///
/// [config] is injectable for tests; production passes the environment config.
Future<void> bootstrap({SupabaseConfig? config}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail fast on missing/invalid configuration — never fall back to a hardcoded
  // or production project, and never continue with a half-initialized client.
  final resolved = (config ?? SupabaseConfig.fromEnvironment()).requireValid();

  // The config field is named `anonKey` (env `SUPABASE_ANON_KEY`), but the SDK
  // parameter is now `publishableKey` (`anonKey` is deprecated in supabase_flutter
  // 2.15). Both legacy anon JWTs and new `sb_publishable_...` keys are accepted.
  await Supabase.initialize(
    url: resolved.url,
    publishableKey: resolved.anonKey,
  );

  runApp(const ProviderScope(child: SumouApp()));
}
