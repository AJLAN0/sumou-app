import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/feature_permissions.dart';
import 'package:sumou_app/core/models/role_type.dart';

void main() {
  group('AppFeature.code ↔ fromCode', () {
    test('every active operational code round-trips', () {
      const active = <String, AppFeature>{
        'can_add_project': AppFeature.canAddProject,
        'can_edit_project': AppFeature.canEditProject,
        'can_assign_photographers': AppFeature.canAssignPhotographers,
        'can_request_photographer': AppFeature.canRequestPhotographer,
        'can_request_design': AppFeature.canRequestDesign,
        'can_update_stages': AppFeature.canUpdateStages,
        'can_request_closure': AppFeature.canRequestClosure,
        'can_approve_closure': AppFeature.canApproveClosure,
        'can_manage_users': AppFeature.canManageUsers,
        'can_manage_permissions': AppFeature.canManagePermissions,
        'can_view_reports': AppFeature.canViewReports,
        'can_manage_attendance': AppFeature.canManageAttendance,
        'can_manage_wedding_projects': AppFeature.canManageWeddingProjects,
      };
      active.forEach((code, feature) {
        expect(AppFeature.fromCode(code), feature, reason: code);
        expect(feature.code, code);
      });
    });

    test('can_manage_finance (inactive/excluded) never maps to a feature', () {
      expect(AppFeature.fromCode('can_manage_finance'), isNull);
      // the enum value still has a stable code for completeness
      expect(AppFeature.canManageFinance.code, 'can_manage_finance');
    });

    test('unknown codes map to null (never grant a capability)', () {
      expect(AppFeature.fromCode('can_do_anything'), isNull);
      expect(AppFeature.fromCode(''), isNull);
      expect(AppFeature.fromCode('CAN_ADD_PROJECT'), isNull);
    });
  });

  group('RoleType.marketing', () {
    test('has the frozen key + labels and round-trips from key', () {
      expect(RoleType.marketing.key, 'marketing');
      expect(RoleType.marketing.nameAr, 'تسويق');
      expect(RoleType.marketing.nameEn, 'Marketing');
      expect(RoleType.fromKey('marketing'), RoleType.marketing);
    });

    test('marketing is distinct from designer', () {
      expect(RoleType.marketing, isNot(RoleType.designer));
      expect(RoleType.fromKey('marketing'), isNot(RoleType.designer));
    });
  });
}
