import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_enums.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/project_stage_model.dart';
import '../../../core/models/project_team_role.dart';
import '../project_repository.dart';
import 'project_gateway.dart';

/// Strict, read-only project repository over authenticated, RLS-scoped rows.
class SupabaseProjectRepository implements ProjectRepository {
  SupabaseProjectRepository(SupabaseClient client)
    : _gateway = SupabaseProjectGateway(client);

  SupabaseProjectRepository.withGateway(this._gateway);

  final ProjectGateway _gateway;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _serial = RegExp(
    r'^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$',
  );
  static final RegExp _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  );
  static final RegExp _photographerTypeCode = RegExp(r'^[a-z][a-z0-9_]{0,49}$');

  @override
  Future<List<ProjectModel>> getProjects() => _loadProjects();

  @override
  Future<ProjectModel?> getProjectById(String id) async {
    final projectId = _inputUuid(id);
    final projects = await _loadProjects(projectId: projectId);
    return projects.isEmpty ? null : projects.single;
  }

  @override
  Future<List<ProjectModel>> getProjectsForManager(String managerId) async {
    final normalized = _inputUuid(managerId);
    final projects = await getProjects();
    return List.unmodifiable(
      projects.where((project) => project.managerId == normalized),
    );
  }

  @override
  Future<List<ProjectModel>> getProjectsForPhotographer(String userId) async {
    final normalized = _inputUuid(userId);
    final projects = await getProjects();
    return List.unmodifiable(
      projects.where((project) => project.isAssignedTo(normalized)),
    );
  }

  @override
  Future<List<ProjectModel>> getCompletedProjects() async {
    final projects = await getProjects();
    return List.unmodifiable(projects.where((project) => project.isCompleted));
  }

  @override
  Future<List<ProjectModel>> searchProjects(String query) async {
    final normalized = query.trim().toLowerCase();
    final projects = await getProjects();
    if (normalized.isEmpty) return projects;
    return List.unmodifiable(
      projects.where((project) {
        final visibleTeamMatch = project.teamRoles.any(
          (role) => role.personName.toLowerCase().contains(normalized),
        );
        return project.name.toLowerCase().contains(normalized) ||
            project.clientName.toLowerCase().contains(normalized) ||
            project.serial.toLowerCase().contains(normalized) ||
            visibleTeamMatch;
      }),
    );
  }

  @override
  Future<List<ProjectModel>> filterProjects({
    ProjectStatus? status,
    ProjectType? type,
  }) async {
    final projects = await getProjects();
    return List.unmodifiable(
      projects.where(
        (project) =>
            (status == null || project.status == status) &&
            (type == null || project.type == type),
      ),
    );
  }

  Future<List<ProjectModel>> _loadProjects({String? projectId}) async {
    try {
      final rawProjects = await _gateway.fetchProjects(projectId: projectId);
      if (rawProjects.isEmpty) return const [];

      final rowsById = <String, _ProjectRow>{};
      final seenProjectIds = <String>{};
      for (final row in rawProjects) {
        final id = _requiredUuid(row, 'id');
        if (!seenProjectIds.add(id)) _invalidData();
        if (!_isLiveProject(row)) continue;
        rowsById[id] = _parseProject(row, id);
      }
      if (rowsById.isEmpty) return const [];

      final projectIds = rowsById.keys.toList(growable: false);
      final graphRows = await Future.wait<List<Map<String, dynamic>>>([
        _gateway.fetchStages(projectIds),
        _gateway.fetchTeamMembers(projectIds),
        _gateway.fetchVisibleProfiles(
          rowsById.values
              .map((project) => project.managerId)
              .toSet()
              .toList(growable: false),
        ),
      ]);
      final stagesByProject = _parseStages(graphRows[0], rowsById);
      final members = _parseTeamMembers(graphRows[1], rowsById);
      final managerNames = _parseVisibleProfiles(
        graphRows[2],
        rowsById.values.map((project) => project.managerId).toSet(),
      );
      final typeRows = await _gateway.fetchTeamTypes(
        members.keys.toList(growable: false),
      );
      final rolesByProject = _parseTeamTypes(typeRows, members);

      final projects = <ProjectModel>[];
      for (final row in rowsById.values) {
        final stages = stagesByProject[row.id] ?? const <ProjectStageModel>[];
        _validateWorkflow(row.type, stages);
        projects.add(
          ProjectModel(
            id: row.id,
            serial: row.serial,
            name: row.name,
            clientName: row.clientName,
            managerId: row.managerId,
            managerName: managerNames[row.managerId],
            type: row.type,
            status: row.status,
            startDate: row.startDate,
            endDate: row.endDate,
            notes: row.notes,
            teamRoles: List.unmodifiable(
              rolesByProject[row.id] ?? const <ProjectTeamRole>[],
            ),
            stages: List.unmodifiable(stages),
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ),
        );
      }
      return List.unmodifiable(projects);
    } on ProjectRepositoryException {
      rethrow;
    } catch (_) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.loadFailed,
      );
    }
  }

  _ProjectRow _parseProject(Map<String, dynamic> row, String id) {
    final type = _parseProjectType(_requiredToken(row, 'type'));
    final serial = _requiredToken(row, 'serial');
    if (!_serial.hasMatch(serial) || !_serialMatchesType(serial, type)) {
      _invalidData();
    }
    final startDate = _requiredDate(row, 'start_date');
    final endDate = _requiredDate(row, 'end_date');
    if (endDate.isBefore(startDate)) _invalidData();
    return _ProjectRow(
      id: id,
      serial: serial,
      name: _requiredText(row, 'name'),
      clientName: _requiredText(row, 'client_name'),
      managerId: _requiredUuid(row, 'manager_id'),
      type: type,
      status: _parseProjectStatus(_requiredToken(row, 'status')),
      startDate: startDate,
      endDate: endDate,
      notes: _optionalString(row, 'notes'),
      createdAt: _requiredTimestamp(row, 'created_at'),
      updatedAt: _requiredTimestamp(row, 'updated_at'),
    );
  }

  Map<String, List<ProjectStageModel>> _parseStages(
    List<Map<String, dynamic>> rows,
    Map<String, _ProjectRow> projects,
  ) {
    final result = <String, List<ProjectStageModel>>{};
    final ids = <String>{};
    final orders = <String, Set<int>>{};
    for (final row in rows) {
      final id = _requiredUuid(row, 'id');
      final projectId = _requiredUuid(row, 'project_id');
      if (!ids.add(id) || !projects.containsKey(projectId)) _invalidData();
      final order = row['stage_order'];
      if (order is! int || order < 1) _invalidData();
      if (!orders.putIfAbsent(projectId, () => <int>{}).add(order)) {
        _invalidData();
      }
      result
          .putIfAbsent(projectId, () => <ProjectStageModel>[])
          .add(
            ProjectStageModel(
              id: id,
              projectId: projectId,
              title: _requiredNonBlankString(row, 'title'),
              order: order,
              status: _parseStageStatus(_requiredToken(row, 'status')),
              notes: _optionalString(row, 'notes'),
              updatedBy: _optionalUuid(row, 'updated_by'),
              updatedAt: _optionalTimestamp(row['updated_at']),
            ),
          );
    }
    for (final stages in result.values) {
      stages.sort((a, b) => a.order.compareTo(b.order));
    }
    return result;
  }

  Map<String, _TeamMember> _parseTeamMembers(
    List<Map<String, dynamic>> rows,
    Map<String, _ProjectRow> projects,
  ) {
    final result = <String, _TeamMember>{};
    final usersByProject = <String, Set<String>>{};
    for (final row in rows) {
      final id = _requiredUuid(row, 'id');
      if (result.containsKey(id)) _invalidData();
      final projectId = _requiredUuid(row, 'project_id');
      if (!projects.containsKey(projectId)) _invalidData();
      final userId = _optionalUuid(row, 'user_id');
      if (userId != null &&
          !usersByProject
              .putIfAbsent(projectId, () => <String>{})
              .add(userId)) {
        _invalidData();
      }
      final value = row['value'];
      if (value is! num || (value is double && !value.isFinite)) {
        _invalidData();
      }
      result[id] = _TeamMember(
        id: id,
        projectId: projectId,
        userId: userId,
        personName: _requiredText(row, 'person_name'),
        value: value,
        date: _optionalDate(row['date']),
      );
    }
    return result;
  }

  Map<String, List<ProjectTeamRole>> _parseTeamTypes(
    List<Map<String, dynamic>> rows,
    Map<String, _TeamMember> members,
  ) {
    final associationIds = <String>{};
    final catalogById = <String, _PhotographerType>{};
    final catalogIdByCode = <String, String>{};
    final typesByMember = <String, List<_MemberType>>{};
    final typeIdsByMember = <String, Set<String>>{};
    final typeCodesByMember = <String, Set<String>>{};

    for (final row in rows) {
      final associationId = _requiredUuid(row, 'id');
      final memberId = _requiredUuid(row, 'team_member_id');
      final typeId = _requiredUuid(row, 'photographer_type_id');
      if (!associationIds.add(associationId) ||
          !members.containsKey(memberId)) {
        _invalidData();
      }
      final embedded = row['photographer_type'];
      if (embedded is! Map) _invalidData();
      final typeRow = Map<String, dynamic>.from(embedded);
      if (_requiredUuid(typeRow, 'id') != typeId ||
          _requiredBool(typeRow, 'is_active') != true) {
        _invalidData();
      }
      final code = _requiredToken(typeRow, 'code');
      final nameAr = _requiredText(typeRow, 'name_ar');
      if (!_photographerTypeCode.hasMatch(code)) _invalidData();

      final catalog = _PhotographerType(id: typeId, code: code, nameAr: nameAr);
      final priorCatalog = catalogById[typeId];
      if (priorCatalog != null &&
          (priorCatalog.code != code || priorCatalog.nameAr != nameAr)) {
        _invalidData();
      }
      final priorId = catalogIdByCode[code];
      if (priorId != null && priorId != typeId) _invalidData();
      catalogById[typeId] = catalog;
      catalogIdByCode[code] = typeId;

      if (!typeIdsByMember
              .putIfAbsent(memberId, () => <String>{})
              .add(typeId) ||
          !typeCodesByMember
              .putIfAbsent(memberId, () => <String>{})
              .add(code)) {
        _invalidData();
      }
      typesByMember
          .putIfAbsent(memberId, () => <_MemberType>[])
          .add(_MemberType(associationId: associationId, type: catalog));
    }

    final result = <String, List<ProjectTeamRole>>{};
    for (final member in members.values) {
      final memberTypes = typesByMember[member.id];
      if (memberTypes == null || memberTypes.isEmpty) _invalidData();
      memberTypes.sort((a, b) => a.type.code.compareTo(b.type.code));
      for (var index = 0; index < memberTypes.length; index++) {
        final memberType = memberTypes[index];
        result
            .putIfAbsent(member.projectId, () => <ProjectTeamRole>[])
            .add(
              ProjectTeamRole(
                id: memberType.associationId,
                projectId: member.projectId,
                type: memberType.type.nameAr,
                personName: member.personName,
                userId: member.userId,
                value: index == 0 ? member.value : 0,
                date: member.date,
              ),
            );
      }
    }
    return result;
  }

  Map<String, String> _parseVisibleProfiles(
    List<Map<String, dynamic>> rows,
    Set<String> requestedIds,
  ) {
    final result = <String, String>{};
    final seen = <String>{};
    for (final row in rows) {
      final id = _requiredUuid(row, 'id');
      if (!requestedIds.contains(id) || !seen.add(id)) _invalidData();
      final active = _requiredBool(row, 'is_active');
      final deletedAt = _optionalTimestamp(row['deleted_at']);
      if (!active || deletedAt != null) continue;
      result[id] = _requiredText(row, 'full_name');
    }
    return result;
  }

  static bool _isLiveProject(Map<String, dynamic> row) {
    final active = _requiredBool(row, 'is_active');
    final deletedAt = _optionalTimestamp(row['deleted_at']);
    return active && deletedAt == null;
  }

  static void _validateWorkflow(
    ProjectType type,
    List<ProjectStageModel> stages,
  ) {
    final titles = type.defaultStageTitles;
    if (stages.length != titles.length) _invalidData();
    for (var index = 0; index < stages.length; index++) {
      final stage = stages[index];
      if (stage.order != index + 1 || stage.title != titles[index]) {
        _invalidData();
      }
    }
  }

  static ProjectType _parseProjectType(String value) => switch (value) {
    'field' => ProjectType.field,
    'social' => ProjectType.social,
    'wedding' => ProjectType.wedding,
    _ => _invalidData(),
  };

  static ProjectStatus _parseProjectStatus(String value) => switch (value) {
    'active' => ProjectStatus.active,
    'completed' => ProjectStatus.completed,
    'pending_closure' => ProjectStatus.pendingClosure,
    'rejected' => ProjectStatus.rejected,
    'approved' => ProjectStatus.approved,
    'in_progress' => ProjectStatus.inProgress,
    'delivered' => ProjectStatus.delivered,
    _ => _invalidData(),
  };

  static ProjectStageStatus _parseStageStatus(String value) => switch (value) {
    'pending' => ProjectStageStatus.pending,
    'current' => ProjectStageStatus.current,
    'done' => ProjectStageStatus.done,
    _ => _invalidData(),
  };

  static bool _serialMatchesType(String serial, ProjectType type) =>
      switch (type) {
        ProjectType.field => serial.startsWith('FLD-'),
        ProjectType.social => serial.startsWith('SOC-'),
        ProjectType.wedding => serial.startsWith('WED-'),
      };

  static String _inputUuid(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_uuid.hasMatch(normalized)) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.invalidInput,
      );
    }
    return normalized;
  }

  static String _requiredUuid(Map<String, dynamic> row, String key) {
    final value = _requiredToken(row, key).toLowerCase();
    if (!_uuid.hasMatch(value)) _invalidData();
    return value;
  }

  static String? _optionalUuid(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String || value != value.trim() || !_uuid.hasMatch(value)) {
      _invalidData();
    }
    return value.toLowerCase();
  }

  static String _requiredToken(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty || value != value.trim()) {
      _invalidData();
    }
    return value;
  }

  static String _requiredNonBlankString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) _invalidData();
    return value;
  }

  static String _requiredText(Map<String, dynamic> row, String key) =>
      _requiredNonBlankString(row, key).trim();

  static String? _optionalString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) _invalidData();
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! bool) _invalidData();
    return value;
  }

  static DateTime _requiredDate(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) _invalidData();
    return _parseDate(value);
  }

  static DateTime? _optionalDate(dynamic value) {
    if (value == null) return null;
    if (value is! String) _invalidData();
    return _parseDate(value);
  }

  static DateTime _parseDate(String value) {
    if (!_dateOnly.hasMatch(value)) _invalidData();
    final parts = value.split('-').map(int.parse).toList(growable: false);
    final date = DateTime(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      _invalidData();
    }
    return date;
  }

  static DateTime _requiredTimestamp(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) _invalidData();
    final parsed = _optionalTimestamp(value);
    if (parsed == null) _invalidData();
    return parsed;
  }

  static DateTime? _optionalTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is! String || !_timestamp.hasMatch(value)) _invalidData();
    _parseDate(value.substring(0, 10));
    final parsed = DateTime.tryParse(value);
    if (parsed == null) _invalidData();
    return parsed.toUtc();
  }

  static Never _invalidData() =>
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.invalidData,
      );

  static Future<T> _unsupported<T>() => Future<T>.error(
    const ProjectRepositoryException(
      ProjectRepositoryFailure.unsupportedOperation,
    ),
  );

  @override
  Future<List<ClosureRequestModel>> getClosureRequests() => _unsupported();

  @override
  Future<ProjectModel> createProject({
    required String name,
    required String clientName,
    required String managerId,
    String? managerName,
    required ProjectType type,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
    String? serial,
    List<ProjectTeamRole> teamRoles = const [],
  }) => _unsupported();

  @override
  Future<ProjectModel?> updateProjectBasics(
    String projectId, {
    required String name,
    required String clientName,
    required ProjectType type,
    required ProjectStatus status,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) => _unsupported();

  @override
  Future<ProjectModel?> setProjectManager(
    String projectId, {
    required String managerId,
    String? managerName,
  }) => _unsupported();

  @override
  Future<ProjectModel?> assignTeamRoles(
    String projectId,
    List<ProjectTeamRole> teamRoles,
  ) => _unsupported();

  @override
  Future<ProjectModel?> updateProjectStage(
    String projectId,
    String stageId, {
    String? notes,
    String? updatedBy,
  }) => _unsupported();

  @override
  Future<ClosureRequestModel?> submitClosureRequest({
    required String projectId,
    required String submittedBy,
    required String submittedByName,
    String? deliveryLink,
    String? reportFileUrl,
    String? notes,
  }) => _unsupported();

  @override
  Future<ClosureRequestModel?> approveClosureRequest(String requestId) =>
      _unsupported();

  @override
  Future<ClosureRequestModel?> rejectClosureRequest(
    String requestId,
    String reason,
  ) => _unsupported();
}

class _ProjectRow {
  const _ProjectRow({
    required this.id,
    required this.serial,
    required this.name,
    required this.clientName,
    required this.managerId,
    required this.type,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String serial;
  final String name;
  final String clientName;
  final String managerId;
  final ProjectType type;
  final ProjectStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class _TeamMember {
  const _TeamMember({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.personName,
    required this.value,
    required this.date,
  });

  final String id;
  final String projectId;
  final String? userId;
  final String personName;
  final num value;
  final DateTime? date;
}

class _PhotographerType {
  const _PhotographerType({
    required this.id,
    required this.code,
    required this.nameAr,
  });

  final String id;
  final String code;
  final String nameAr;
}

class _MemberType {
  const _MemberType({required this.associationId, required this.type});

  final String associationId;
  final _PhotographerType type;
}
