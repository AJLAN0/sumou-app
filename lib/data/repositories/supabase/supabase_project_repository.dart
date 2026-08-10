import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/models/assignable_project_staff.dart';
import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_delivery_link.dart';
import '../../../core/models/project_enums.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/project_stage_model.dart';
import '../../../core/models/project_team_role.dart';
import '../project_repository.dart';
import 'project_gateway.dart';

/// Strict project repository over authenticated, RLS-scoped reads and the
/// explicitly approved project write RPCs.
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
    r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d'
    r'(?:\.\d+)?(?:Z|[+-](?:0\d|1[0-5]):[0-5]\d)$',
  );
  static const Set<String> _assignableCandidateKeys = {
    'user_id',
    'full_name',
    'photographer_types',
    'is_available',
  };
  static const Set<String> _assignableTypeKeys = {'id', 'code', 'name_ar'};
  static const Set<String> _assignableTypeCodes = {
    'photo',
    'video',
    'instagram',
    'design',
  };
  static const Set<String> _closureRequestKeys = {
    'id',
    'project_id',
    'project_name',
    'submitted_by',
    'submitted_by_name',
    'created_at',
    'report_file_url',
    'delivery_link',
    'notes',
    'status',
    'reject_reason',
    'reviewed_at',
  };
  static const Set<String> _projectLinkKeys = {
    'id',
    'project_id',
    'label',
    'url',
    'is_approved',
    'is_client_visible',
    'is_active',
    'created_at',
    'deleted_at',
  };

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
  Future<List<AssignableProjectStaff>> getAssignableProjectStaff({
    required DateTime onDate,
    String? excludeProjectId,
  }) async {
    final normalizedDate = _inputDate(onDate);
    final normalizedExcludeProjectId =
        excludeProjectId == null ? null : _inputStrictUuid(excludeProjectId);

    try {
      final response = await _gateway.listAssignableProjectStaff(
        onDate: normalizedDate,
        excludeProjectId: normalizedExcludeProjectId,
      );
      if (response is! List) _invalidData();

      final candidates = <AssignableProjectStaff>[];
      final seenUserIds = <String>{};
      for (final rawCandidate in response) {
        final candidate = _strictMap(rawCandidate, _assignableCandidateKeys);
        final userId = _requiredUuid(candidate, 'user_id');
        if (!seenUserIds.add(userId)) _invalidData();

        final rawTypes = candidate['photographer_types'];
        if (rawTypes is! List || rawTypes.isEmpty) _invalidData();
        final photographerTypes = <ProjectPhotographerType>[];
        final seenTypeIds = <String>{};
        final seenTypeCodes = <String>{};
        for (final rawType in rawTypes) {
          final type = _strictMap(rawType, _assignableTypeKeys);
          final id = _requiredUuid(type, 'id');
          final code = _requiredToken(type, 'code');
          if (!_assignableTypeCodes.contains(code) ||
              !seenTypeIds.add(id) ||
              !seenTypeCodes.add(code)) {
            _invalidData();
          }
          photographerTypes.add(
            ProjectPhotographerType(
              id: id,
              code: code,
              nameAr: _requiredText(type, 'name_ar'),
            ),
          );
        }

        candidates.add(
          AssignableProjectStaff(
            userId: userId,
            fullName: _requiredText(candidate, 'full_name'),
            photographerTypes: photographerTypes,
            isAvailable: _requiredBool(candidate, 'is_available'),
          ),
        );
      }
      return List.unmodifiable(candidates);
    } on ProjectGatewayException catch (error) {
      final reason = switch (error.reason) {
        ProjectGatewayFailure.notAuthenticated =>
          ProjectRepositoryFailure.notAuthenticated,
        ProjectGatewayFailure.forbidden => ProjectRepositoryFailure.forbidden,
        ProjectGatewayFailure.invalidInput =>
          ProjectRepositoryFailure.invalidInput,
        ProjectGatewayFailure.unavailable =>
          ProjectRepositoryFailure.unavailable,
        ProjectGatewayFailure.missingEntity =>
          ProjectRepositoryFailure.notFound,
        ProjectGatewayFailure.serverFailure =>
          ProjectRepositoryFailure.loadFailed,
      };
      throw ProjectRepositoryException(reason);
    } on ProjectRepositoryException {
      rethrow;
    } catch (_) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.loadFailed,
      );
    }
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
      final date = _optionalDate(row['date']);
      if (userId != null && date == null) _invalidData();
      result[id] = _TeamMember(
        id: id,
        projectId: projectId,
        userId: userId,
        personName: _requiredText(row, 'person_name'),
        value: value,
        date: date,
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
      if (!_assignableTypeCodes.contains(code)) _invalidData();

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
                teamMemberId: member.id,
                photographerTypeId: memberType.type.id,
                photographerTypeCode: memberType.type.code,
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

  static String _inputStrictUuid(String value) {
    if (value != value.trim() || !_uuid.hasMatch(value)) _invalidInput();
    return value.toLowerCase();
  }

  static Map<String, dynamic> _strictMap(
    Object? value,
    Set<String> expectedKeys,
  ) {
    if (value is! Map) _invalidData();
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) _invalidData();
      result[entry.key as String] = entry.value;
    }
    if (result.length != expectedKeys.length ||
        !result.keys.toSet().containsAll(expectedKeys)) {
      _invalidData();
    }
    return result;
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

  static Never _invalidInput() =>
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.invalidInput,
      );

  static String _inputText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) _invalidInput();
    return normalized;
  }

  static String? _inputNotes(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _inputDate(DateTime value) {
    if (value.hour != 0 ||
        value.minute != 0 ||
        value.second != 0 ||
        value.millisecond != 0 ||
        value.microsecond != 0) {
      _invalidInput();
    }
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${twoDigits(value.month)}-${twoDigits(value.day)}';
  }

  static String _rpcUuid(Object? value) {
    if (value is! String || value != value.trim() || !_uuid.hasMatch(value)) {
      _invalidData();
    }
    return value.toLowerCase();
  }

  Future<ProjectModel> _requireProjectForWrite(String projectId) async {
    final projects = await _loadProjects(projectId: projectId);
    if (projects.isEmpty) {
      throw const ProjectRepositoryException(ProjectRepositoryFailure.notFound);
    }
    return projects.single;
  }

  Future<ProjectModel> _requireProjectAfterWrite(String projectId) async {
    final projects = await _loadProjects(projectId: projectId);
    if (projects.isEmpty) _invalidData();
    return projects.single;
  }

  Future<T> _performWrite<T>(
    Future<T> Function() action, {
    required bool missingEntityIsUnavailable,
  }) async {
    try {
      return await action();
    } on ProjectGatewayException catch (error) {
      final reason = switch (error.reason) {
        ProjectGatewayFailure.notAuthenticated =>
          ProjectRepositoryFailure.notAuthenticated,
        ProjectGatewayFailure.forbidden => ProjectRepositoryFailure.forbidden,
        ProjectGatewayFailure.invalidInput =>
          ProjectRepositoryFailure.invalidInput,
        ProjectGatewayFailure.unavailable =>
          ProjectRepositoryFailure.unavailable,
        ProjectGatewayFailure.missingEntity =>
          missingEntityIsUnavailable
              ? ProjectRepositoryFailure.unavailable
              : ProjectRepositoryFailure.notFound,
        ProjectGatewayFailure.serverFailure =>
          ProjectRepositoryFailure.saveFailed,
      };
      throw ProjectRepositoryException(reason);
    } on ProjectRepositoryException catch (error) {
      if (error.reason == ProjectRepositoryFailure.loadFailed) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.saveFailed,
        );
      }
      rethrow;
    } catch (_) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.saveFailed,
      );
    }
  }

  static bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static bool _sameTeam(
    List<ProjectTeamRole> before,
    List<ProjectTeamRole> after,
  ) {
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      final left = before[index];
      final right = after[index];
      if (left.id != right.id ||
          left.projectId != right.projectId ||
          left.type != right.type ||
          left.personName != right.personName ||
          left.teamMemberId != right.teamMemberId ||
          left.photographerTypeId != right.photographerTypeId ||
          left.photographerTypeCode != right.photographerTypeCode ||
          left.userId != right.userId ||
          left.value != right.value ||
          (left.date == null) != (right.date == null) ||
          (left.date != null && !_sameDate(left.date!, right.date!))) {
        return false;
      }
    }
    return true;
  }

  Future<List<_NormalizedTeamMember>> _normalizeTeamRoles(
    List<ProjectTeamRole> roles, {
    required String? excludeProjectId,
    required bool allowExistingExternal,
    required bool preflightInternal,
  }) async {
    final groups = <String, _MutableTeamMember>{};
    final typeIdsByCode = <String, String>{};
    final typeCodesById = <String, String>{};

    for (final role in roles) {
      final typeIdValue = role.photographerTypeId;
      final typeCode = role.photographerTypeCode;
      if (typeIdValue == null ||
          typeCode == null ||
          !_assignableTypeCodes.contains(typeCode)) {
        _invalidInput();
      }
      final typeId = _inputStrictUuid(typeIdValue);
      final knownId = typeIdsByCode[typeCode];
      final knownCode = typeCodesById[typeId];
      if ((knownId != null && knownId != typeId) ||
          (knownCode != null && knownCode != typeCode)) {
        _invalidInput();
      }
      typeIdsByCode[typeCode] = typeId;
      typeCodesById[typeId] = typeCode;

      final value = role.value;
      if (!value.isFinite) _invalidInput();

      final String key;
      final String? userId;
      final String? externalName;
      final DateTime? date;
      if (role.userId != null) {
        userId = _inputStrictUuid(role.userId!);
        externalName = null;
        if (role.date == null) _invalidInput();
        _inputDate(role.date!);
        date = role.date;
        key = 'user:$userId';
      } else {
        if (!allowExistingExternal || role.teamMemberId == null) {
          _invalidInput();
        }
        final memberId = _inputStrictUuid(role.teamMemberId!);
        userId = null;
        externalName = _inputText(role.personName);
        if (role.date != null) _inputDate(role.date!);
        date = role.date;
        key = 'external:$memberId';
      }

      final group = groups.putIfAbsent(
        key,
        () => _MutableTeamMember(
          key: key,
          userId: userId,
          externalName: externalName,
          value: value,
          date: date,
        ),
      );
      if (group.userId != userId ||
          group.externalName != externalName ||
          !_sameNullableDate(group.date, date)) {
        _invalidInput();
      }
      if (group.types.isNotEmpty && value != 0) {
        if (group.value != 0) _invalidInput();
        group.value = value;
      }
      if (!group.typeIds.add(typeId) || !group.typeCodes.add(typeCode)) {
        _invalidInput();
      }
      group.types.add(_NormalizedTeamType(id: typeId, code: typeCode));
    }

    final normalized = [
      for (final group in groups.values)
        _NormalizedTeamMember(
          key: group.key,
          userId: group.userId,
          externalName: group.externalName,
          value: group.value,
          date: group.date,
          types: List.unmodifiable(
            group.types..sort((a, b) => a.code.compareTo(b.code)),
          ),
        ),
    ]..sort(
      (a, b) => _normalizedMemberComparisonKey(
        a,
      ).compareTo(_normalizedMemberComparisonKey(b)),
    );

    if (preflightInternal) {
      final candidatesByDate = <String, List<AssignableProjectStaff>>{};
      for (final member in normalized.where(
        (member) => member.userId != null,
      )) {
        final date = member.date!;
        final dateKey = _inputDate(date);
        List<AssignableProjectStaff> candidates;
        try {
          candidates =
              candidatesByDate[dateKey] ??= await getAssignableProjectStaff(
                onDate: date,
                excludeProjectId: excludeProjectId,
              );
        } on ProjectRepositoryException catch (error) {
          if (error.reason == ProjectRepositoryFailure.notFound) {
            throw const ProjectRepositoryException(
              ProjectRepositoryFailure.unavailable,
            );
          }
          rethrow;
        }
        final candidate =
            candidates
                .where((item) => item.userId == member.userId)
                .firstOrNull;
        if (candidate == null || !candidate.isAvailable) {
          throw const ProjectRepositoryException(
            ProjectRepositoryFailure.unavailable,
          );
        }
        final allowedTypes = {
          for (final type in candidate.photographerTypes) type.id: type.code,
        };
        for (final type in member.types) {
          if (allowedTypes[type.id] != type.code) {
            throw const ProjectRepositoryException(
              ProjectRepositoryFailure.unavailable,
            );
          }
        }
      }
    }

    return List.unmodifiable(normalized);
  }

  static List<Map<String, dynamic>> _teamPayload(
    List<_NormalizedTeamMember> members,
  ) => [
    for (final member in members)
      {
        'user_id': member.userId,
        'person_name': member.userId == null ? member.externalName : null,
        'value': member.value,
        'date': member.date == null ? null : _inputDate(member.date!),
        'photographer_type_ids': [for (final type in member.types) type.id],
      },
  ];

  static bool _sameNullableDate(DateTime? left, DateTime? right) =>
      left == null ? right == null : right != null && _sameDate(left, right);

  static bool _sameNormalizedTeam(
    List<_NormalizedTeamMember> expected,
    List<_NormalizedTeamMember> actual,
  ) {
    if (expected.length != actual.length) return false;
    for (var index = 0; index < expected.length; index++) {
      final left = expected[index];
      final right = actual[index];
      if (left.userId != right.userId ||
          left.externalName != right.externalName ||
          left.value != right.value ||
          !_sameNullableDate(left.date, right.date) ||
          left.types.length != right.types.length) {
        return false;
      }
      for (var typeIndex = 0; typeIndex < left.types.length; typeIndex++) {
        if (left.types[typeIndex] != right.types[typeIndex]) return false;
      }
    }
    return true;
  }

  static String _normalizedMemberComparisonKey(_NormalizedTeamMember member) {
    final identity = member.userId ?? 'external:${member.externalName}';
    final date = member.date == null ? '' : _inputDate(member.date!);
    final types = member.types
        .map((type) => '${type.id}:${type.code}')
        .join(',');
    return '$identity|$date|${member.value}|$types';
  }

  static bool _sameProjectOutsideTeam(
    ProjectModel before,
    ProjectModel after,
  ) =>
      before.id == after.id &&
      before.serial == after.serial &&
      before.name == after.name &&
      before.clientName == after.clientName &&
      before.managerId == after.managerId &&
      before.type == after.type &&
      before.status == after.status &&
      _sameDate(before.startDate, after.startDate) &&
      _sameDate(before.endDate, after.endDate) &&
      before.notes == after.notes &&
      _sameStages(before.stages, after.stages);

  static bool _sameStages(
    List<ProjectStageModel> before,
    List<ProjectStageModel> after,
  ) {
    if (before.length != after.length) return false;
    final afterById = {for (final stage in after) stage.id: stage};
    if (afterById.length != after.length) return false;
    for (final left in before) {
      final right = afterById[left.id];
      if (right == null ||
          left.projectId != right.projectId ||
          left.title != right.title ||
          left.order != right.order ||
          left.status != right.status ||
          left.notes != right.notes ||
          left.updatedBy != right.updatedBy ||
          left.updatedAt != right.updatedAt) {
        return false;
      }
    }
    return true;
  }

  List<ClosureRequestModel> _parseClosureRequests(Object? response) {
    if (response is! List) _invalidData();
    final requests = <ClosureRequestModel>[];
    final ids = <String>{};
    for (final raw in response) {
      final row = _strictMap(raw, _closureRequestKeys);
      final id = _requiredUuid(row, 'id');
      if (!ids.add(id)) _invalidData();

      final status = switch (_requiredToken(row, 'status')) {
        'pending' => ClosureRequestStatus.pending,
        'approved' => ClosureRequestStatus.approved,
        'rejected' => ClosureRequestStatus.rejected,
        _ => _invalidData(),
      };
      final reviewedAt = _optionalTimestamp(row['reviewed_at']);
      final rejectReason = _optionalString(row, 'reject_reason');
      switch (status) {
        case ClosureRequestStatus.pending:
          if (reviewedAt != null || rejectReason != null) _invalidData();
        case ClosureRequestStatus.approved:
          if (reviewedAt == null || rejectReason != null) _invalidData();
        case ClosureRequestStatus.rejected:
          if (reviewedAt == null ||
              rejectReason == null ||
              rejectReason.trim().isEmpty) {
            _invalidData();
          }
      }

      final deliveryLink = _optionalString(row, 'delivery_link');
      if (deliveryLink != null) _validateHttpUrlData(deliveryLink);
      requests.add(
        ClosureRequestModel(
          id: id,
          projectId: _requiredUuid(row, 'project_id'),
          projectName: _requiredNonBlankString(row, 'project_name'),
          submittedBy: _requiredUuid(row, 'submitted_by'),
          submittedByName: _requiredNonBlankString(row, 'submitted_by_name'),
          createdAt: _requiredTimestamp(row, 'created_at'),
          reportFileUrl: _optionalString(row, 'report_file_url'),
          deliveryLink: deliveryLink,
          notes: _optionalString(row, 'notes'),
          status: status,
          rejectReason: rejectReason,
          reviewedAt: reviewedAt,
        ),
      );
    }
    return List.unmodifiable(requests);
  }

  List<ProjectDeliveryLink> _parseProjectLinks(
    List<Map<String, dynamic>> rows,
    String projectId,
  ) {
    final links = <ProjectDeliveryLink>[];
    final ids = <String>{};
    for (final raw in rows) {
      final row = _strictMap(raw, _projectLinkKeys);
      final id = _requiredUuid(row, 'id');
      if (!ids.add(id) || _requiredUuid(row, 'project_id') != projectId) {
        _invalidData();
      }
      final url = _requiredToken(row, 'url');
      _validateHttpUrlData(url);
      links.add(
        ProjectDeliveryLink(
          id: id,
          projectId: projectId,
          label: _requiredText(row, 'label'),
          url: url,
          isApproved: _requiredBool(row, 'is_approved'),
          isClientVisible: _requiredBool(row, 'is_client_visible'),
          isActive: _requiredBool(row, 'is_active'),
          createdAt: _requiredTimestamp(row, 'created_at'),
          deletedAt: _optionalTimestamp(row['deleted_at']),
        ),
      );
    }
    return List.unmodifiable(links);
  }

  static void _validateHttpUrlData(String value) {
    if (value != value.trim()) _invalidData();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _invalidData();
    }
  }

  static String? _inputHttpUrl(String? value) {
    final normalized = _inputNotes(value);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _invalidInput();
    }
    return normalized;
  }

  static ClosureRequestModel? _closureById(
    List<ClosureRequestModel> requests,
    String requestId,
  ) => requests.where((request) => request.id == requestId).firstOrNull;

  static ProjectRepositoryFailure _readFailure(
    ProjectGatewayFailure reason,
  ) => switch (reason) {
    ProjectGatewayFailure.notAuthenticated =>
      ProjectRepositoryFailure.notAuthenticated,
    ProjectGatewayFailure.forbidden => ProjectRepositoryFailure.forbidden,
    ProjectGatewayFailure.invalidInput ||
    ProjectGatewayFailure.unavailable ||
    ProjectGatewayFailure.missingEntity ||
    ProjectGatewayFailure.serverFailure => ProjectRepositoryFailure.loadFailed,
  };

  static Future<T> _unsupported<T>() => Future<T>.error(
    const ProjectRepositoryException(
      ProjectRepositoryFailure.unsupportedOperation,
    ),
  );

  @override
  Future<List<ClosureRequestModel>> getClosureRequests() async {
    try {
      return _parseClosureRequests(await _gateway.listVisibleClosureRequests());
    } on ProjectGatewayException catch (error) {
      throw ProjectRepositoryException(_readFailure(error.reason));
    } on ProjectRepositoryException {
      rethrow;
    } catch (_) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.loadFailed,
      );
    }
  }

  @override
  Future<List<ProjectDeliveryLink>> getProjectLinks(String projectId) async {
    final normalizedProjectId = _inputStrictUuid(projectId);
    try {
      return _parseProjectLinks(
        await _gateway.fetchProjectLinks(normalizedProjectId),
        normalizedProjectId,
      );
    } on ProjectGatewayException catch (error) {
      throw ProjectRepositoryException(_readFailure(error.reason));
    } on ProjectRepositoryException {
      rethrow;
    } catch (_) {
      throw const ProjectRepositoryException(
        ProjectRepositoryFailure.loadFailed,
      );
    }
  }

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
  }) async {
    if (serial != null) _invalidInput();
    final normalizedName = _inputText(name);
    final normalizedClientName = _inputText(clientName);
    final normalizedManagerId = _inputUuid(managerId);
    final normalizedStartDate = _inputDate(startDate);
    final normalizedEndDate = _inputDate(endDate);
    if (normalizedEndDate.compareTo(normalizedStartDate) < 0) _invalidInput();
    final normalizedNotes = _inputNotes(notes);

    return _performWrite(() async {
      final normalizedTeam = await _normalizeTeamRoles(
        teamRoles,
        excludeProjectId: null,
        allowExistingExternal: false,
        preflightInternal: true,
      );
      final result = await _gateway.createProject({
        'p_name': normalizedName,
        'p_client_name': normalizedClientName,
        'p_type': type.key,
        'p_start_date': normalizedStartDate,
        'p_end_date': normalizedEndDate,
        'p_notes': normalizedNotes,
        'p_manager_id': normalizedManagerId,
        'p_members': _teamPayload(normalizedTeam),
      });
      final createdId = _rpcUuid(result);
      final created = await _requireProjectAfterWrite(createdId);
      if (created.id != createdId ||
          created.name != normalizedName ||
          created.clientName != normalizedClientName ||
          created.managerId != normalizedManagerId ||
          created.type != type ||
          !_sameDate(created.startDate, startDate) ||
          !_sameDate(created.endDate, endDate) ||
          created.notes != normalizedNotes) {
        _invalidData();
      }
      final createdTeam = await _normalizeTeamRoles(
        created.teamRoles,
        excludeProjectId: null,
        allowExistingExternal: true,
        preflightInternal: false,
      );
      if (!_sameNormalizedTeam(normalizedTeam, createdTeam)) _invalidData();
      return created;
    }, missingEntityIsUnavailable: true);
  }

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
  }) async {
    final normalizedProjectId = _inputUuid(projectId);
    final normalizedName = _inputText(name);
    final normalizedClientName = _inputText(clientName);
    final normalizedStartDate = _inputDate(startDate);
    final normalizedEndDate = _inputDate(endDate);
    if (normalizedEndDate.compareTo(normalizedStartDate) < 0) _invalidInput();
    final normalizedNotes = _inputNotes(notes);

    return _performWrite(() async {
      final before = await _requireProjectForWrite(normalizedProjectId);
      if (!before.isActive) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }
      if (type != before.type || status != before.status) _invalidInput();

      final result = await _gateway.updateProject({
        'p_project_id': normalizedProjectId,
        'p_name': normalizedName,
        'p_client_name': normalizedClientName,
        'p_type': before.type.key,
        'p_start_date': normalizedStartDate,
        'p_end_date': normalizedEndDate,
        'p_notes': normalizedNotes,
      });
      if (_rpcUuid(result) != normalizedProjectId) _invalidData();

      final updated = await _requireProjectAfterWrite(normalizedProjectId);
      if (updated.name != normalizedName ||
          updated.clientName != normalizedClientName ||
          updated.type != before.type ||
          updated.status != before.status ||
          !_sameDate(updated.startDate, startDate) ||
          !_sameDate(updated.endDate, endDate) ||
          updated.notes != normalizedNotes ||
          updated.serial != before.serial ||
          updated.managerId != before.managerId) {
        _invalidData();
      }
      return updated;
    }, missingEntityIsUnavailable: false);
  }

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
  ) async {
    final normalizedProjectId = _inputStrictUuid(projectId);

    return _performWrite(() async {
      final before = await _requireProjectForWrite(normalizedProjectId);
      if (!before.isActive) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }

      final preservedExternalRoles = before.teamRoles
          .where((role) => role.userId == null)
          .toList(growable: false);
      final proposedInternalRoles = teamRoles.where(
        (role) => role.userId != null,
      );
      final proposedExternalRoles = teamRoles
          .where((role) => role.userId == null)
          .toList(growable: false);
      if (proposedExternalRoles.isNotEmpty) {
        final proposedExternal = await _normalizeTeamRoles(
          proposedExternalRoles,
          excludeProjectId: normalizedProjectId,
          allowExistingExternal: true,
          preflightInternal: false,
        );
        final persistedExternal = await _normalizeTeamRoles(
          preservedExternalRoles,
          excludeProjectId: normalizedProjectId,
          allowExistingExternal: true,
          preflightInternal: false,
        );
        if (!_sameNormalizedTeam(proposedExternal, persistedExternal)) {
          _invalidInput();
        }
      }
      final normalizedTeam = await _normalizeTeamRoles(
        [...proposedInternalRoles, ...preservedExternalRoles],
        excludeProjectId: normalizedProjectId,
        allowExistingExternal: true,
        preflightInternal: true,
      );

      final result = await _gateway.assignTeamRoles({
        'p_project_id': normalizedProjectId,
        'p_members': _teamPayload(normalizedTeam),
      });
      if (_rpcUuid(result) != normalizedProjectId) _invalidData();

      final updated = await _requireProjectAfterWrite(normalizedProjectId);
      if (!_sameProjectOutsideTeam(before, updated)) _invalidData();
      final updatedTeam = await _normalizeTeamRoles(
        updated.teamRoles,
        excludeProjectId: normalizedProjectId,
        allowExistingExternal: true,
        preflightInternal: false,
      );
      if (!_sameNormalizedTeam(normalizedTeam, updatedTeam)) _invalidData();
      return updated;
    }, missingEntityIsUnavailable: true);
  }

  @override
  Future<ProjectModel?> updateProjectStage(
    String projectId,
    String stageId, {
    String? notes,
    String? updatedBy,
  }) async {
    final normalizedProjectId = _inputUuid(projectId);
    final normalizedStageId = _inputUuid(stageId);
    final normalizedNotes = _inputNotes(notes);

    return _performWrite(() async {
      final before = await _requireProjectForWrite(normalizedProjectId);
      if (!before.isActive) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }
      final target =
          before.stages
              .where((stage) => stage.id == normalizedStageId)
              .firstOrNull;
      if (target == null) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.notFound,
        );
      }

      final result = await _gateway.updateProjectStage({
        'p_project_id': normalizedProjectId,
        'p_stage_id': normalizedStageId,
        'p_notes': normalizedNotes,
      });
      if (_rpcUuid(result) != normalizedProjectId) _invalidData();

      final updated = await _requireProjectAfterWrite(normalizedProjectId);
      if (updated.id != before.id ||
          updated.serial != before.serial ||
          updated.name != before.name ||
          updated.clientName != before.clientName ||
          updated.managerId != before.managerId ||
          updated.type != before.type ||
          updated.status != before.status ||
          !_sameDate(updated.startDate, before.startDate) ||
          !_sameDate(updated.endDate, before.endDate) ||
          updated.notes != before.notes ||
          !_sameTeam(before.teamRoles, updated.teamRoles) ||
          updated.stages.length != before.stages.length) {
        _invalidData();
      }
      final beforeById = {for (final stage in before.stages) stage.id: stage};
      for (final stage in updated.stages) {
        final prior = beforeById[stage.id];
        if (prior == null ||
            stage.projectId != prior.projectId ||
            stage.title != prior.title ||
            stage.order != prior.order) {
          _invalidData();
        }
        final expectedStatus = switch (stage.order.compareTo(target.order)) {
          < 0 => ProjectStageStatus.done,
          0 => ProjectStageStatus.current,
          _ => ProjectStageStatus.pending,
        };
        if (stage.status != expectedStatus ||
            (stage.id == normalizedStageId
                ? stage.notes != normalizedNotes
                : stage.notes != prior.notes)) {
          _invalidData();
        }
      }
      return updated;
    }, missingEntityIsUnavailable: false);
  }

  @override
  Future<ClosureRequestModel?> submitClosureRequest({
    required String projectId,
    required String submittedBy,
    required String submittedByName,
    String? deliveryLink,
    String? reportFileUrl,
    String? notes,
  }) async {
    final normalizedProjectId = _inputStrictUuid(projectId);
    final normalizedDeliveryLink = _inputHttpUrl(deliveryLink);
    final normalizedReportFileUrl = _inputNotes(reportFileUrl);
    final normalizedNotes = _inputNotes(notes);

    return _performWrite(() async {
      final result = await _gateway.submitClosureRequest({
        'p_project_id': normalizedProjectId,
        'p_delivery_link': normalizedDeliveryLink,
        'p_report_file_url': normalizedReportFileUrl,
        'p_notes': normalizedNotes,
      });
      final requestId = _rpcUuid(result);
      final request = _closureById(await getClosureRequests(), requestId);
      if (request == null ||
          request.projectId != normalizedProjectId ||
          request.status != ClosureRequestStatus.pending ||
          request.deliveryLink != normalizedDeliveryLink ||
          request.reportFileUrl != normalizedReportFileUrl ||
          request.notes != normalizedNotes) {
        _invalidData();
      }
      final project = await _requireProjectAfterWrite(normalizedProjectId);
      if (project.status != ProjectStatus.pendingClosure) _invalidData();
      return request;
    }, missingEntityIsUnavailable: true);
  }

  @override
  Future<ClosureRequestModel?> approveClosureRequest(String requestId) async {
    final normalizedRequestId = _inputStrictUuid(requestId);
    return _performWrite(() async {
      final before = _closureById(
        await getClosureRequests(),
        normalizedRequestId,
      );
      if (before == null) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.notFound,
        );
      }
      if (!before.isPending) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }

      final result = await _gateway.approveClosureRequest({
        'p_request_id': normalizedRequestId,
      });
      if (_rpcUuid(result) != normalizedRequestId) _invalidData();

      final request = _closureById(
        await getClosureRequests(),
        normalizedRequestId,
      );
      if (request == null ||
          request.projectId != before.projectId ||
          !request.isApproved ||
          request.reviewedAt == null ||
          request.rejectReason != null) {
        _invalidData();
      }
      final project = await _requireProjectAfterWrite(before.projectId);
      if (project.status != ProjectStatus.completed ||
          project.stages.any((stage) => !stage.isDone)) {
        _invalidData();
      }
      return request;
    }, missingEntityIsUnavailable: true);
  }

  @override
  Future<ClosureRequestModel?> rejectClosureRequest(
    String requestId,
    String reason,
  ) async {
    final normalizedRequestId = _inputStrictUuid(requestId);
    final normalizedReason = _inputText(reason);
    return _performWrite(() async {
      final before = _closureById(
        await getClosureRequests(),
        normalizedRequestId,
      );
      if (before == null) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.notFound,
        );
      }
      if (!before.isPending) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }

      final result = await _gateway.rejectClosureRequest({
        'p_request_id': normalizedRequestId,
        'p_reason': normalizedReason,
      });
      if (_rpcUuid(result) != normalizedRequestId) _invalidData();

      final request = _closureById(
        await getClosureRequests(),
        normalizedRequestId,
      );
      if (request == null ||
          request.projectId != before.projectId ||
          !request.isRejected ||
          request.rejectReason != normalizedReason ||
          request.reviewedAt == null) {
        _invalidData();
      }
      final project = await _requireProjectAfterWrite(before.projectId);
      if (project.status != ProjectStatus.active) _invalidData();
      return request;
    }, missingEntityIsUnavailable: true);
  }
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

class _MutableTeamMember {
  _MutableTeamMember({
    required this.key,
    required this.userId,
    required this.externalName,
    required this.value,
    required this.date,
  });

  final String key;
  final String? userId;
  final String? externalName;
  num value;
  final DateTime? date;
  final List<_NormalizedTeamType> types = [];
  final Set<String> typeIds = {};
  final Set<String> typeCodes = {};
}

class _NormalizedTeamMember {
  const _NormalizedTeamMember({
    required this.key,
    required this.userId,
    required this.externalName,
    required this.value,
    required this.date,
    required this.types,
  });

  final String key;
  final String? userId;
  final String? externalName;
  final num value;
  final DateTime? date;
  final List<_NormalizedTeamType> types;
}

class _NormalizedTeamType {
  const _NormalizedTeamType({required this.id, required this.code});

  final String id;
  final String code;

  @override
  bool operator ==(Object other) =>
      other is _NormalizedTeamType && other.id == id && other.code == code;

  @override
  int get hashCode => Object.hash(id, code);
}
