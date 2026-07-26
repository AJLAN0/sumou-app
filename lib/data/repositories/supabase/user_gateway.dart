import 'package:supabase_flutter/supabase_flutter.dart';

/// Status + decoded body from an admin user-management Edge Function.
class AdminUserFunctionResponse {
  const AdminUserFunctionResponse({required this.status, required this.data});

  final int status;
  final dynamic data;
}

Map<String, dynamic> adminCreateUserRequestBody({
  required String username,
  required String fullName,
  required String defaultRole,
  required List<String> roles,
  required List<String> photographerTypes,
  required List<Map<String, dynamic>> permissionOverrides,
}) => {
  'username': username,
  'full_name': fullName,
  'default_role': defaultRole,
  'roles': roles,
  'photographer_types': photographerTypes,
  'permission_overrides': permissionOverrides,
};

Map<String, String> adminResetPasswordRequestBody(String userId) => {
  'user_id': userId,
};

/// Narrow, fakeable boundary for admin-readable RLS queries and the two trusted
/// user-management Edge Functions. It never exposes Auth users or emails.
abstract interface class UserAdminGateway {
  Future<List<Map<String, dynamic>>> fetchProfiles({
    String? userId,
    String? username,
  });
  Future<List<Map<String, dynamic>>> fetchRoleAssignments(List<String> userIds);
  Future<List<Map<String, dynamic>>> fetchPhotoTypeAssignments(
    List<String> userIds,
  );
  Future<List<Map<String, dynamic>>> fetchRolePermissions(List<String> roleIds);
  Future<List<Map<String, dynamic>>> fetchUserPermissions(List<String> userIds);
  Future<List<Map<String, dynamic>>> fetchActivePhotoTypes();
  Future<AdminUserFunctionResponse> invokeCreateUser(Map<String, dynamic> body);
  Future<AdminUserFunctionResponse> invokeResetPassword(
    Map<String, String> body,
  );
}

class SupabaseUserAdminGateway implements UserAdminGateway {
  const SupabaseUserAdminGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles({
    String? userId,
    String? username,
  }) async {
    final query = _client
        .from('profiles')
        .select(
          'id, username, full_name, avatar_initials, is_active, deleted_at, '
          'default_role_id, must_change_password',
        );
    final List<dynamic> rows;
    if (userId != null) {
      rows = await query.eq('id', userId);
    } else if (username != null) {
      rows = await query.eq('username', username);
    } else {
      rows = await query.order('full_name');
    }
    return _maps(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoleAssignments(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await _client
        .from('user_roles')
        .select('user_id, role_id, roles!inner(id, code, is_active)')
        .inFilter('user_id', userIds);
    return [
      for (final raw in rows)
        {
          'user_id': (raw as Map)['user_id'],
          'role_id': raw['role_id'],
          'role': _embed(raw['roles']),
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPhotoTypeAssignments(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await _client
        .from('user_photographer_types')
        .select('user_id, photographer_types!inner(code, name_ar, is_active)')
        .inFilter('user_id', userIds);
    return [
      for (final raw in rows)
        {
          'user_id': (raw as Map)['user_id'],
          'photographer_type': _embed(raw['photographer_types']),
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRolePermissions(
    List<String> roleIds,
  ) async {
    if (roleIds.isEmpty) return const [];
    final rows = await _client
        .from('role_permissions')
        .select('role_id, granted, permissions!inner(code, is_active)')
        .inFilter('role_id', roleIds);
    return [
      for (final raw in rows)
        {
          'role_id': (raw as Map)['role_id'],
          'granted': raw['granted'],
          'permission': _embed(raw['permissions']),
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserPermissions(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await _client
        .from('user_permissions')
        .select('user_id, granted, permissions!inner(code, is_active)')
        .inFilter('user_id', userIds);
    return [
      for (final raw in rows)
        {
          'user_id': (raw as Map)['user_id'],
          'granted': raw['granted'],
          'permission': _embed(raw['permissions']),
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActivePhotoTypes() async {
    final rows = await _client
        .from('photographer_types')
        .select('code, name_ar, is_active')
        .eq('is_active', true)
        .order('name_ar');
    return _maps(rows);
  }

  @override
  Future<AdminUserFunctionResponse> invokeCreateUser(
    Map<String, dynamic> body,
  ) => _invoke('admin-create-user', body);

  @override
  Future<AdminUserFunctionResponse> invokeResetPassword(
    Map<String, String> body,
  ) => _invoke('admin-reset-password', body);

  Future<AdminUserFunctionResponse> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    try {
      // The initialized caller-scoped client supplies the authenticated bearer.
      // No service_role key or custom identity is ever accepted here.
      final response = await _client.functions.invoke(functionName, body: body);
      return AdminUserFunctionResponse(
        status: response.status,
        data: response.data,
      );
    } on FunctionException catch (error) {
      return AdminUserFunctionResponse(
        status: error.status,
        data: error.details,
      );
    }
  }

  static List<Map<String, dynamic>> _maps(List<dynamic> rows) => [
    for (final row in rows) Map<String, dynamic>.from(row as Map),
  ];

  static Map<String, dynamic>? _embed(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.length == 1 && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }
}
