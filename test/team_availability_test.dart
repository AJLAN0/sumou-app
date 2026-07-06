// Unit tests for the mock team-availability rules used by the create-project
// team step (same-date booking + leave locking).

import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/features/projects/team_availability.dart';

ProjectModel _project({
  required String id,
  required String assignedUserId,
  required DateTime start,
  required DateTime end,
  ProjectStatus status = ProjectStatus.active,
}) {
  return ProjectModel(
    id: id,
    serial: 'x',
    name: 'n',
    clientName: 'c',
    managerId: 'm',
    type: ProjectType.field,
    status: status,
    startDate: start,
    endDate: end,
    teamRoles: [
      ProjectTeamRole(
        id: '$id-r1',
        projectId: id,
        type: 'مصور فوتوغرافي',
        personName: 'شخص',
        userId: assignedUserId,
      ),
    ],
  );
}

void main() {
  final booked = _project(
    id: 'p1',
    assignedUserId: 'u-1',
    start: DateTime(2026, 8, 1),
    end: DateTime(2026, 8, 5),
  );

  test('isBookedOn covers the project date range (inclusive)', () {
    expect(isBookedOn('u-1', DateTime(2026, 8, 1), [booked]), isTrue);
    expect(isBookedOn('u-1', DateTime(2026, 8, 3), [booked]), isTrue);
    expect(isBookedOn('u-1', DateTime(2026, 8, 5), [booked]), isTrue);
    // Outside the range or a different user.
    expect(isBookedOn('u-1', DateTime(2026, 8, 6), [booked]), isFalse);
    expect(isBookedOn('u-2', DateTime(2026, 8, 3), [booked]), isFalse);
  });

  test('isBookedOn can exclude a project and ignores non-active ones', () {
    expect(
      isBookedOn('u-1', DateTime(2026, 8, 3), [booked], excludeProjectId: 'p1'),
      isFalse,
    );
    final completed = _project(
      id: 'p2',
      assignedUserId: 'u-1',
      start: DateTime(2026, 8, 1),
      end: DateTime(2026, 8, 5),
      status: ProjectStatus.completed,
    );
    expect(isBookedOn('u-1', DateTime(2026, 8, 3), [completed]), isFalse);
  });

  test('MockLeave flags seeded leave dates only', () {
    expect(MockLeave.isOnLeave('u-photographer', DateTime(2026, 8, 10)), isTrue);
    expect(
      MockLeave.isOnLeave('u-photographer', DateTime(2026, 8, 11)),
      isFalse,
    );
    expect(MockLeave.isOnLeave('u-other', DateTime(2026, 8, 10)), isFalse);
  });

  test('availabilityLockFor resolves booking and leave reasons', () {
    const user = UserModel(
      id: 'u-1',
      fullName: 'شخص',
      username: 'p1',
      defaultRole: RoleType.photographer,
      roles: [RoleType.photographer],
    );
    expect(
      availabilityLockFor(user, DateTime(2026, 8, 3), [booked]),
      AvailabilityLock.booked,
    );
    expect(
      availabilityLockFor(user, DateTime(2026, 8, 6), [booked]),
      AvailabilityLock.none,
    );

    const onLeave = UserModel(
      id: 'u-photographer',
      fullName: 'نورة',
      username: 'photographer',
      defaultRole: RoleType.photographer,
      roles: [RoleType.photographer],
    );
    expect(
      availabilityLockFor(onLeave, DateTime(2026, 8, 10), const []),
      AvailabilityLock.onLeave,
    );

    // Reasons are Arabic and match the spec wording.
    expect(AvailabilityLock.booked.reasonAr, 'محجوز في نفس التاريخ');
    expect(AvailabilityLock.onLeave.reasonAr, 'لديه إذن في نفس اليوم');
  });

  test('marketing exemption hook is inert (no Marketing role yet)', () {
    const user = UserModel(
      id: 'u-1',
      fullName: 'شخص',
      username: 'p1',
      defaultRole: RoleType.photographer,
      roles: [RoleType.photographer],
    );
    expect(isMarketingExempt(user), isFalse);
  });
}
