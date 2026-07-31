import 'package:supabase_flutter/supabase_flutter.dart';

enum ProjectGatewayFailure {
  notAuthenticated,
  forbidden,
  invalidInput,
  unavailable,
  missingEntity,
  serverFailure,
}

class ProjectGatewayException implements Exception {
  const ProjectGatewayException(this.reason);

  final ProjectGatewayFailure reason;

  @override
  String toString() => 'ProjectGatewayException(${reason.name})';
}

/// Narrow, fakeable boundary for authenticated, RLS-scoped project access.
abstract interface class ProjectGateway {
  Future<List<Map<String, dynamic>>> fetchProjects({String? projectId});

  Future<List<Map<String, dynamic>>> fetchStages(List<String> projectIds);

  Future<List<Map<String, dynamic>>> fetchTeamMembers(List<String> projectIds);

  Future<List<Map<String, dynamic>>> fetchTeamTypes(List<String> teamMemberIds);

  Future<List<Map<String, dynamic>>> fetchVisibleProfiles(
    List<String> profileIds,
  );

  Future<Object?> createProject(Map<String, dynamic> parameters);

  Future<Object?> updateProject(Map<String, dynamic> parameters);

  Future<Object?> updateProjectStage(Map<String, dynamic> parameters);
}

class SupabaseProjectGateway implements ProjectGateway {
  const SupabaseProjectGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchProjects({String? projectId}) async {
    final query = _client
        .from('projects')
        .select(
          'id, serial, name, client_name, manager_id, type, status, '
          'start_date, end_date, notes, is_active, created_at, updated_at, '
          'deleted_at',
        )
        .eq('is_active', true)
        .isFilter('deleted_at', null);
    final List<dynamic> rows;
    if (projectId != null) {
      rows = await query.eq('id', projectId);
    } else {
      rows = await query.order('created_at', ascending: false);
    }
    return _maps(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStages(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return const [];
    final rows = await _client
        .from('project_stages')
        .select(
          'id, project_id, title, stage_order, status, notes, updated_by, '
          'updated_at',
        )
        .inFilter('project_id', projectIds)
        .order('project_id')
        .order('stage_order');
    return _maps(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeamMembers(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return const [];
    final rows = await _client
        .from('project_team_members')
        .select('id, project_id, user_id, person_name, value, date')
        .inFilter('project_id', projectIds)
        .order('project_id')
        .order('person_name');
    return _maps(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeamTypes(
    List<String> teamMemberIds,
  ) async {
    if (teamMemberIds.isEmpty) return const [];
    final rows = await _client
        .from('project_team_types')
        .select(
          'id, team_member_id, photographer_type_id, '
          'photographer_types!inner(id, code, name_ar, is_active)',
        )
        .inFilter('team_member_id', teamMemberIds)
        .eq('photographer_types.is_active', true)
        .order('team_member_id');
    return [
      for (final raw in rows)
        {
          'id': (raw as Map)['id'],
          'team_member_id': raw['team_member_id'],
          'photographer_type_id': raw['photographer_type_id'],
          'photographer_type': _embed(raw['photographer_types']),
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchVisibleProfiles(
    List<String> profileIds,
  ) async {
    if (profileIds.isEmpty) return const [];
    final rows = await _client
        .from('profiles')
        .select('id, full_name, is_active, deleted_at')
        .inFilter('id', profileIds);
    return _maps(rows);
  }

  @override
  Future<Object?> createProject(Map<String, dynamic> parameters) =>
      _rpc('create_project', parameters);

  @override
  Future<Object?> updateProject(Map<String, dynamic> parameters) =>
      _rpc('update_project', parameters);

  @override
  Future<Object?> updateProjectStage(Map<String, dynamic> parameters) =>
      _rpc('update_project_stage', parameters);

  Future<Object?> _rpc(
    String functionName,
    Map<String, dynamic> parameters,
  ) async {
    try {
      return await _client.rpc(functionName, params: parameters);
    } on PostgrestException catch (error) {
      throw ProjectGatewayException(_safeFailure(error.code));
    }
  }

  static ProjectGatewayFailure _safeFailure(String? code) => switch (code) {
    '28000' || 'PGRST301' => ProjectGatewayFailure.notAuthenticated,
    '42501' => ProjectGatewayFailure.forbidden,
    '22023' => ProjectGatewayFailure.invalidInput,
    'P0001' => ProjectGatewayFailure.unavailable,
    'P0002' => ProjectGatewayFailure.missingEntity,
    _ => ProjectGatewayFailure.serverFailure,
  };

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
