import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../data/repositories/mock/mock_repositories.dart';
import '../../data/repositories/supabase/supabase_auth_repository.dart';
import 'supabase_providers.dart';

/// Repository dependency-injection providers.
///
/// Auth is now Supabase-backed in the normal app; the other repositories still
/// return in-memory mocks until their Supabase implementations land. Callers
/// depend on the abstract interfaces, so swapping an implementation here (or
/// overriding in a [ProviderScope]) needs no changes above.
///
/// TESTS and previews must explicitly override [authRepositoryProvider] with a
/// [MockAuthRepository] (see `test/test_helpers.dart` `mockAuthOverrides`). The
/// mock is NEVER selected implicitly by build mode or a "under test" check.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => MockUserRepository(),
);

final permissionRepositoryProvider = Provider<PermissionRepository>(
  (ref) => MockPermissionRepository(),
);

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => MockTrackingRepository(),
);

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => MockProjectRepository(),
);
