import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../data/repositories/mock/mock_repositories.dart';
import '../../data/repositories/supabase/supabase_auth_repository.dart';
import '../../data/repositories/supabase/supabase_project_repository.dart';
import '../../data/repositories/supabase/supabase_tracking_repository.dart';
import '../../data/repositories/supabase/supabase_user_repository.dart';
import 'supabase_providers.dart';

/// Repository dependency-injection providers.
///
/// Auth, admin users, projects, and public tracking are Supabase-backed in the
/// normal app. Callers depend on abstract interfaces; tests and previews that
/// need deterministic data must override repositories explicitly.
///
/// TESTS and previews must explicitly override [authRepositoryProvider] with a
/// [MockAuthRepository] (see `test/test_helpers.dart` `mockAuthOverrides`). The
/// mock is NEVER selected implicitly by build mode or runtime detection.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => SupabaseUserRepository(ref.watch(supabaseClientProvider)),
);

final permissionRepositoryProvider = Provider<PermissionRepository>(
  (ref) => MockPermissionRepository(),
);

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => SupabaseTrackingRepository(ref.watch(supabaseClientProvider)),
);

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => SupabaseProjectRepository(ref.watch(supabaseClientProvider)),
);
