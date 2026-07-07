import 'package:flutter/material.dart' show DateUtils;

import '../../core/models/models.dart';

/// Why a team member can't be picked for a given project date.
enum AvailabilityLock { none, booked, onLeave }

extension AvailabilityLockView on AvailabilityLock {
  bool get isLocked => this != AvailabilityLock.none;

  /// Short Arabic explanation shown on a locked photographer card.
  String? get reasonAr => switch (this) {
    AvailabilityLock.none => null,
    AvailabilityLock.booked => 'محجوز في نفس التاريخ',
    AvailabilityLock.onLeave => 'لديه إذن في نفس اليوم',
  };
}

/// Mock leave/permission calendar: user id → leave dates (date-only).
///
/// Placeholder data only — there is no attendance/leave module yet. A real
/// source replaces this later without touching callers.
class MockLeave {
  MockLeave._();

  static final Map<String, Set<DateTime>> _byUser = {
    // Example permission so the locking is visible in the mock data.
    'u-photographer': {DateTime(2026, 8, 10)},
  };

  static bool isOnLeave(String userId, DateTime date) {
    final d = DateUtils.dateOnly(date);
    return _byUser[userId]?.contains(d) ?? false;
  }
}

/// Inert hook: marketing staff may be booked on more than one project on the
/// same date. There is no Marketing role in the app yet, so this always returns
/// false — flip it on once such a role exists.
bool isMarketingExempt(UserModel user) => false;

/// True when [userId] is already assigned to an active project whose date range
/// covers [date] (optionally ignoring [excludeProjectId]).
bool isBookedOn(
  String userId,
  DateTime date,
  List<ProjectModel> projects, {
  String? excludeProjectId,
}) {
  final d = DateUtils.dateOnly(date);
  for (final p in projects) {
    if (p.id == excludeProjectId) continue;
    if (!p.isActive) continue;
    if (!p.isAssignedTo(userId)) continue;
    final start = DateUtils.dateOnly(p.startDate);
    final end = DateUtils.dateOnly(p.endDate);
    if (!d.isBefore(start) && !d.isAfter(end)) return true;
  }
  return false;
}

/// Resolve why [user] can't be assigned on [date] (or [AvailabilityLock.none]).
/// Marketing-exempt users are never locked.
AvailabilityLock availabilityLockFor(
  UserModel user,
  DateTime date,
  List<ProjectModel> projects, {
  String? excludeProjectId,
}) {
  if (isMarketingExempt(user)) return AvailabilityLock.none;
  if (MockLeave.isOnLeave(user.id, date)) return AvailabilityLock.onLeave;
  if (isBookedOn(user.id, date, projects, excludeProjectId: excludeProjectId)) {
    return AvailabilityLock.booked;
  }
  return AvailabilityLock.none;
}
