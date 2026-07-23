import 'feature_permissions.dart';
import 'role_type.dart';

/// An app user (staff member).
///
/// Holds identity, roles, photo types, and resolved feature [permissions].
/// Pure Dart value type with small helpers for the auth/role flows.
class UserModel {
  const UserModel({
    required this.id,
    required this.fullName,
    required this.username,
    required this.defaultRole,
    this.email,
    String? avatarInitials,
    this.active = true,
    this.mustChangePassword = false,
    this.roles = const [],
    this.photoTypes = const [],
    this.permissions = const FeaturePermissions(),
  }) : _avatarInitials = avatarInitials;

  final String id;
  final String fullName;
  final String username;
  final String? email;
  final bool active;

  /// Whether the backend requires this user to change their password on next
  /// login (`profiles.must_change_password`). Step 10.5 **loads and preserves**
  /// this flag only — no forced-change routing yet (that is Step 10.6). Defaults
  /// to `false` for mock/test users.
  final bool mustChangePassword;
  final RoleType defaultRole;
  final List<RoleType> roles;
  final List<String> photoTypes;
  final FeaturePermissions permissions;

  final String? _avatarInitials;

  /// Initials shown in avatars; computed from [fullName] when not provided.
  String get avatarInitials => _avatarInitials ?? initialsFrom(fullName);

  /// True when the user holds more than one role and must pick one on login.
  bool get hasMultipleRoles => roles.length > 1;

  /// True when the account is enabled (disabled users cannot log in).
  bool get isActive => active;

  bool hasRole(RoleType role) => roles.contains(role);
  bool hasPermission(AppFeature feature) => permissions.has(feature);
  bool hasPhotoType(String type) => photoTypes.contains(type);

  /// The role to route to: the [defaultRole] when held, else the first role,
  /// else the [defaultRole] as a last resort.
  RoleType get effectiveRole {
    if (roles.contains(defaultRole)) return defaultRole;
    if (roles.isNotEmpty) return roles.first;
    return defaultRole;
  }

  /// Derive up-to-two-character initials from a full name (Arabic or Latin).
  static String initialsFrom(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final only = parts.first;
      return only.length <= 2 ? only : only.substring(0, 2);
    }
    return parts[0].substring(0, 1) + parts[1].substring(0, 1);
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? username,
    String? email,
    String? avatarInitials,
    bool? active,
    bool? mustChangePassword,
    RoleType? defaultRole,
    List<RoleType>? roles,
    List<String>? photoTypes,
    FeaturePermissions? permissions,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      email: email ?? this.email,
      avatarInitials: avatarInitials ?? _avatarInitials,
      active: active ?? this.active,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      defaultRole: defaultRole ?? this.defaultRole,
      roles: roles ?? this.roles,
      photoTypes: photoTypes ?? this.photoTypes,
      permissions: permissions ?? this.permissions,
    );
  }
}
