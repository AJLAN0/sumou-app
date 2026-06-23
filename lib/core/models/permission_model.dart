import 'feature_permissions.dart';
import 'role_type.dart';

/// A user's permission record: their active state, roles, photo types, and
/// feature flags. Mirrors the `user_permissions` shape in the spec.
///
/// Pure Dart value type — no Flutter, no backend coupling.
class PermissionModel {
  const PermissionModel({
    required this.userId,
    this.active = true,
    this.roles = const [],
    this.photoTypes = const [],
    this.features = const FeaturePermissions(),
  });

  final String userId;
  final bool active;
  final List<RoleType> roles;
  final List<String> photoTypes;
  final FeaturePermissions features;

  bool get isActive => active;
  bool get hasMultipleRoles => roles.length > 1;

  bool hasRole(RoleType role) => roles.contains(role);
  bool hasPermission(AppFeature feature) => features.has(feature);
  bool hasPhotoType(String type) => photoTypes.contains(type);

  PermissionModel copyWith({
    String? userId,
    bool? active,
    List<RoleType>? roles,
    List<String>? photoTypes,
    FeaturePermissions? features,
  }) {
    return PermissionModel(
      userId: userId ?? this.userId,
      active: active ?? this.active,
      roles: roles ?? this.roles,
      photoTypes: photoTypes ?? this.photoTypes,
      features: features ?? this.features,
    );
  }
}
