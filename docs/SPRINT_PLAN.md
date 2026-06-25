# Sumou Mobile App — Sprint Plan (Sprint 1 & Sprint 2)

> Scope sequencing for the Sumou Mobile App. Requirements detail lives in
> `EXTRACTED_REQUIREMENTS.md`. Only **Sprint 1** and **Sprint 2** are planned
> here; everything else is explicitly deferred (see "Out of scope / Later").

---

## Sprint goals at a glance

| Sprint | Theme | Outcome |
|--------|-------|---------|
| **Sprint 1** | Core Foundation / MVP base | App boots in Arabic RTL with Sumou theme, the design system, mock auth, multi-role detection, role-based shell + bottom nav, per-role dashboards, profile/settings, client-tracking entry shell. |
| **Sprint 2** | Basic project management | Manager and photographer can run the project lifecycle end-to-end on mock data: create → assign → stages → closure → approve/reject. |

---

## Sprint 1 — Core Foundation / MVP Base

### In scope
1. Flutter project setup (folder structure, packages, environment config).
2. App theme using Sumou identity (colors, typography, shapes).
3. RTL-first Arabic layout (global `Directionality`, intl, Arabic strings).
4. Splash screen.
5. Entry screen — **دخول سمو** / **تتبع مشروع**.
6. Login screen (mock auth).
7. Secure auth abstraction (`AuthRepository`, no hardcoded secrets).
8. `UserModel`, `RoleModel`, `PermissionModel`.
9. Multi-role detection (`defaultRole` + `extraRoles`).
10. Role selection screen (shown only when >1 role).
11. Role-based routing (go_router with redirect guards).
12. Bottom navigation shell (`MainShellScreen` + `RoleBasedBottomNav`).
13. Reusable `SumouAppBar` / `AppHeader`.
14. Reusable cards, badges, buttons, status chips (design-system components).
15. Basic dashboard layout for each role (full for manager/photographer/admin,
    placeholders for the rest with correct nav).
16. Profile / settings page.
17. Change-password UI.
18. Logout flow.
19. Client-tracking **entry shell**: `TrackProjectScreen` →
    `ClientProjectResultScreen` resolving a code to a status view (mock).

### Sprint 1 deliverable / definition of done
- App launches to Splash → Entry; both entry paths reachable.
- Mock login authenticates; disabled users are rejected.
- Single-role user lands directly on their dashboard; multi-role user sees Role
  Selection then their dashboard.
- Bottom nav and visible actions change with the selected role.
- Manager, photographer, and admin dashboards render with real-looking mock
  cards; other roles show branded placeholders.
- Profile, change-password, logout, and client-tracking shell all work.
- Everything is RTL, on-brand, with loading/empty/error states wired in the
  shared components.

---

## Sprint 2 — Basic Project Management

### In scope
1. Projects list (Manager «المشاريع», Photographer «مشاريعي»).
2. Project details page (header, stage progress, team cards, notes, actions).
3. Create project flow — **5-step form** (basic info → client/date → manager →
   team roles → notes & review) with auto-generated serial.
4. Assign photographers flow.
5. Basic project stages — **generic engine** supporting 3-stage and 7-stage.
6. Basic closure request (photographer submits report file + delivery link).
7. Manager approve/reject closure request.
8. Photographer "My Projects".
9. Completed projects list («المنجزة»).
10. Basic search / filter (All · Active · Done · Field · Social · Pending
    closure; search by project/client/photographer name).
11. Basic project status chips.
12. Basic team/member assignment cards (with simple monthly capacity indicator).

### Sprint 2 deliverable / definition of done
- Manager creates a project via the step form; it appears in the projects list.
- Manager assigns photographers; assignment cards reflect the team.
- Photographer sees the project under "My Projects", advances its stage.
- Photographer submits a closure request (file + link).
- Manager sees the closure request and approves (project → done) or rejects
  (with reason; project stays active).
- Completed projects appear under «المنجزة».
- Search and filters work on list screens; status chips render consistently.
- Capacity indicator shows available/full per photographer (UI-level
  calculation; assignment blocking is later).

---

## Cross-sprint engineering tracks

- **Design system first:** build `Sumou*` components before screens consume them.
- **Mock-data backbone:** in-memory mock repositories implement the repository
  interfaces; UI never calls a backend directly.
- **Repository interfaces stable:** `AuthRepository`, `UserRepository`,
  `ProjectRepository`, `PermissionRepository`, `TrackingRepository` defined in
  Sprint 1, reused in Sprint 2. `NotificationRepository`'s interface may stay
  declared, but it gets **no implementation** (notifications are permanently out
  of scope).
- **Supabase-ready, not Supabase-bound:** keep schema notes for the listed
  tables; do not wire live Supabase in these two sprints unless trivial.

---

## Permanently out of scope (do NOT implement)

These are **permanently out of scope** for all current and future sprints —
**not** "for later." Do not implement, wire, or schedule them unless the project
owner explicitly requests them. (See the **Permanent Out of Scope** section in
`CLAUDE.md`, which is authoritative.) Existing nav entries/stub screens for
these may remain **only** as inert branded placeholders.

- **Finance module / finance feature logic.**
- **Finance transfer / payment flow** (payment requests, receipts, transfers).
- **Finance reports.**
- **Rekaz configuration** and **Rekaz integration** (API key never in the app).
- **Notifications** — notification logic, in-app notifications, **push
  notifications**, **FCM**.
- **`NotificationRepository` implementation** (no working/mock impl, no
  notifications UI).

## Out of scope / Placeholder for later

These are **deferred** (may return in a later sprint). Provide navigation entry
points and stub screens where the nav demands it, but **do not implement the
logic now**:

- Full wedding system (assignment → upload → approval). *(Its finance leg is
  permanently out of scope per the section above.)*
- GPS attendance / check-in.
- Advanced reports. *(Finance reports are permanently out of scope.)*
- Advanced calendar (full month grid / scheduling).
- Full file uploads (Supabase Storage).
- App Store / Play Store deployment.
- Full client delivery-link approval flow.
- Photographer broadcast-request realtime fan-out (model now, flow later).
- Designer, wedding_admin, attendance, personal_photo feature logic
  (placeholders with correct nav only).
- `finance`, `wedding_finance` roles: **placeholder nav only** — their feature
  logic is permanently out of scope (finance).

---

## Suggested build order (priority)

1. Theme + design system.
2. Mock models + mock data.
3. Auth / entry / role selection.
4. Role-based shell + bottom nav.
5. Manager dashboard.
6. Projects list + project cards.
7. Project details.
8. Add-project flow.
9. Assign-photographer flow.
10. Photographer "My Projects".
11. Stages UI (generic).
12. Closure-request UI.
13. Manager approve/reject UI.
14. Admin users/permissions basic UI.
15. Placeholders for later modules.
