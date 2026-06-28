/// Repository for in-app notifications.
///
/// Declared so the folder structure / dependency wiring stay consistent, but
/// intentionally left empty: notifications are **permanently out of scope** (see
/// the "Permanent Out of Scope" section in `CLAUDE.md`). Do not add methods, an
/// implementation, or a provider unless the project owner explicitly requests
/// notifications later.
abstract interface class NotificationRepository {
  // Intentionally empty — notifications are out of scope.
}
