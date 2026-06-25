// Tests for the Sprint 2 project models and mock repository.

import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';

void main() {
  group('ProjectType', () {
    test('stage flow + titles per type', () {
      expect(ProjectType.social.isSevenStage, isTrue);
      expect(ProjectType.field.isThreeStage, isTrue);
      expect(ProjectType.wedding.isThreeStage, isTrue);
      expect(ProjectStageTitles.threeStage.length, 3);
      expect(ProjectStageTitles.sevenStage.length, 7);
      expect(ProjectType.fromKey('social'), ProjectType.social);
      expect(ProjectType.fromKey('nope'), isNull);
    });
  });

  group('ProjectModel helpers', () {
    test('active field project', () {
      final p = MockProjects.activeField;
      expect(p.isActive, isTrue);
      expect(p.isCompleted, isFalse);
      expect(p.hasPendingClosure, isFalse);
      expect(p.supportsThreeStageFlow, isTrue);
      expect(p.supportsSevenStageFlow, isFalse);
      expect(p.currentStage?.order, 2);
      expect(p.stageProgressPercent, 33); // 1 of 3 done
      expect(p.assignedPhotographers, ['u-photographer']);
      expect(p.isAssignedTo('u-photographer'), isTrue);
    });

    test('social project uses the 7-stage flow', () {
      final p = MockProjects.activeSocial;
      expect(p.supportsSevenStageFlow, isTrue);
      expect(p.stages.length, 7);
      expect(p.stageProgressPercent, 43); // 3 of 7 done
    });

    test('completed project', () {
      final p = MockProjects.completed;
      expect(p.isCompleted, isTrue);
      expect(p.isActive, isFalse);
      expect(p.stageProgressPercent, 100);
    });

    test('pending-closure project', () {
      expect(MockProjects.pendingClosure.hasPendingClosure, isTrue);
    });
  });

  group('MockProjectRepository', () {
    final repo = MockProjectRepository();

    test('getProjects / getProjectById', () async {
      expect((await repo.getProjects()).length, 4);
      expect((await repo.getProjectById('p-3'))?.isCompleted, isTrue);
      expect(await repo.getProjectById('missing'), isNull);
    });

    test('manager / photographer / completed queries', () async {
      expect((await repo.getProjectsForManager('u-manager')).length, 4);
      expect(
        (await repo.getProjectsForPhotographer('u-photographer')).length,
        4,
      );
      expect((await repo.getCompletedProjects()).length, 1);
    });

    test('search by name / client / serial', () async {
      expect((await repo.searchProjects('رمضان')).single.id, 'p-2');
      expect((await repo.searchProjects('النخيل')).single.id, 'p-2');
      expect((await repo.searchProjects('WED-2Q3R-4S')).single.id, 'p-4');
    });

    test('filter by status / type', () async {
      final completed = await repo.filterProjects(
        status: ProjectStatus.completed,
      );
      expect(completed.single.id, 'p-3');
      final weddings = await repo.filterProjects(type: ProjectType.wedding);
      expect(weddings.single.id, 'p-4');
    });

    test('closure requests', () async {
      final requests = await repo.getClosureRequests();
      expect(requests.length, 1);
      expect(requests.single.isPending, isTrue);
    });
  });
}
