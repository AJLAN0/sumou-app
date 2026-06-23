// Unit tests for core models and their helper methods.

import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';

void main() {
  group('RoleType', () {
    test('key/label round-trips via fromKey', () {
      for (final role in RoleType.values) {
        expect(RoleType.fromKey(role.key), role);
      }
      expect(RoleType.fromKey('unknown'), isNull);
    });
  });

  group('FeaturePermissions', () {
    test('defaults are all false', () {
      const perms = FeaturePermissions();
      for (final f in AppFeature.values) {
        expect(perms.has(f), isFalse);
      }
    });

    test('manager defaults can add and approve, photographer cannot', () {
      final manager = FeaturePermissions.defaultsFor(RoleType.manager);
      expect(manager.has(AppFeature.canAddProject), isTrue);
      expect(manager.has(AppFeature.canApproveClosure), isTrue);

      final photographer =
          FeaturePermissions.defaultsFor(RoleType.photographer);
      expect(photographer.has(AppFeature.canAddProject), isFalse);
      expect(photographer.has(AppFeature.canRequestClosure), isTrue);
    });

    test('copyWith overrides a single flag', () {
      const base = FeaturePermissions();
      final updated = base.copyWith(canViewReports: true);
      expect(updated.has(AppFeature.canViewReports), isTrue);
      expect(updated.has(AppFeature.canAddProject), isFalse);
    });
  });

  group('UserModel helpers', () {
    const singleRole = UserModel(
      id: '1',
      fullName: 'نورة الحنايا',
      username: 'noura',
      defaultRole: RoleType.photographer,
      roles: [RoleType.photographer],
    );

    const multiRole = UserModel(
      id: '2',
      fullName: 'سعد المطيري',
      username: 'saad',
      defaultRole: RoleType.manager,
      roles: [RoleType.manager, RoleType.photographer],
    );

    test('hasMultipleRoles', () {
      expect(singleRole.hasMultipleRoles, isFalse);
      expect(multiRole.hasMultipleRoles, isTrue);
    });

    test('isActive reflects active flag', () {
      expect(singleRole.isActive, isTrue);
      expect(singleRole.copyWith(active: false).isActive, isFalse);
    });

    test('effectiveRole prefers the default role when held', () {
      expect(multiRole.effectiveRole, RoleType.manager);
    });

    test('hasPermission reads the resolved feature set', () {
      final manager = singleRole.copyWith(
        permissions: FeaturePermissions.defaultsFor(RoleType.manager),
      );
      expect(manager.hasPermission(AppFeature.canAddProject), isTrue);
      expect(singleRole.hasPermission(AppFeature.canAddProject), isFalse);
    });

    test('initials derived from full name', () {
      expect(UserModel.initialsFrom('نورة الحنايا'), 'ن' 'ا');
      expect(singleRole.avatarInitials.isNotEmpty, isTrue);
    });
  });

  group('ClientTrackingModel', () {
    test('isCreating when there are no approved links', () {
      const model = ClientTrackingModel(
        serial: 'X7K-29QM-4R',
        projectName: 'حملة رمضان',
        clientName: 'شركة النخيل',
        status: 'active',
      );
      expect(model.isCreating, isTrue);
      expect(model.hasApprovedLinks, isFalse);
    });

    test('hasApprovedLinks when a link exists', () {
      const model = ClientTrackingModel(
        serial: 'X7K-29QM-4R',
        projectName: 'حملة رمضان',
        clientName: 'شركة النخيل',
        status: 'done',
        approvedLinks: [DeliveryLink(label: 'الصور', url: 'https://x.test/a')],
      );
      expect(model.isCreating, isFalse);
      expect(model.hasApprovedLinks, isTrue);
    });
  });
}
