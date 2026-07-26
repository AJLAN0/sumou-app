import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single canonical access point for the initialized [SupabaseClient]
/// (Sprint 10 Step 10.4).
///
/// Supabase is initialized once in `bootstrap()` before `runApp`; this provider
/// simply surfaces `Supabase.instance.client`. Repositories and controllers must
/// read the client through **this** provider — widgets must never call
/// `Supabase.instance.client` directly.
///
/// Step 10.4 only *exposes* the client. No repository consumes it yet: the app
/// still authenticates through the mock `authRepositoryProvider`. A Supabase-
/// backed `AuthRepository` (Step 10.5+) will depend on this provider.
///
/// Reading this before initialization throws — that is intentional (fail fast),
/// and tests either override this provider or initialize Supabase first.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
