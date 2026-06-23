# Sumou Mobile App — Implementation Checklist (Sprint 1 & 2)

> Actionable task list. Check items off as they land. Covers **Sprint 1** and
> **Sprint 2** only; later modules appear at the end as **placeholders**.
> No Flutter code is written yet — this is the build map.

Legend: `[ ]` todo · `[~]` placeholder/stub only (later) · 🔒 = security gate.

---

## 0. Project setup & foundation

- [ ] Initialize Flutter project (`sumou-app`), confirm iOS + Android targets.
- [ ] Add packages: `flutter_riverpod` (or `provider`), `go_router`,
      `supabase_flutter`, `intl`, `flutter_svg`, `shared_preferences`
      (lightweight session only), `table_calendar` (only if needed later),
      `image_picker`/`file_picker` (later).
- [ ] Create scalable folder structure under `lib/` (app, theme, localization,
      core, features, data/repositories with `mock/` and `supabase/`).
- [ ] 🔒 Environment/config layer for keys — **no secrets committed**, **no
      Rekaz key in the app**.
- [ ] Global RTL: `Directionality(textDirection: TextDirection.rtl)` + `intl`
      Arabic locale.

---

## 1. Theme & design system (build first)

- [ ] `app_colors.dart` — all brand tokens from `EXTRACTED_REQUIREMENTS.md §6`.
- [ ] `app_text_styles.dart` — Alexandria (or fallback), Arabic-friendly sizes.
- [ ] `app_theme.dart` — dark theme, rounded corners 12–18px, ≥44px targets.
- [ ] `app_strings.dart` — Arabic-primary strings (English prepared).
- [ ] Components:
  - [ ] `SumouScaffold`
  - [ ] `SumouAppBar` / `AppHeader`
  - [ ] `SumouBottomNav`
  - [ ] `SumouCard`
  - [ ] `SumouButton`
  - [ ] `SumouTextField`
  - [ ] `SumouDropdown`
  - [ ] `SumouStatusChip` (8 statuses, consistent colors)
  - [ ] `SumouStatCard`
  - [ ] `SumouProjectCard`
  - [ ] `SumouUserCard`
  - [ ] `SumouSectionHeader`
  - [ ] `SumouEmptyState`
  - [ ] `SumouBottomSheet`
  - [ ] `SumouStepForm`
  - [ ] `SumouProgressTimeline` (generic 3/7-stage)

---

## 2. Models & mock data

- [ ] `UserModel`, `RoleModel`, `PermissionModel`.
- [ ] `ProjectModel`, `ProjectTeamRole`, `ProjectStageModel`.
- [ ] `ClosureRequestModel`, `PhotoRequestModel`, `NotificationModel`.
- [ ] `ClientTrackingModel`.
- [ ] Enums: roles (10), project types (field/social/wedding), 13 photo types,
      status vocabulary, feature-permission flags.
- [ ] Stage definitions: 3-stage and 7-stage sets.
- [ ] Mock data set (users with single + multi-role, projects, stages, closure
      requests, a trackable serial) — **demo passwords are mock-only**, not real.

---

## 3. Repository layer (interfaces + mock impl)

- [ ] `AuthRepository` (+ mock).
- [ ] `UserRepository` (+ mock).
- [ ] `ProjectRepository` (+ mock).
- [ ] `PermissionRepository` (+ mock).
- [ ] `NotificationRepository` (+ mock).
- [ ] `TrackingRepository` (+ mock).
- [ ] 🔒 UI never calls a backend directly — only through repositories.
- [~] Supabase implementations (later) for tables listed in
      `EXTRACTED_REQUIREMENTS.md §7`.

---

## 4. Routing (go_router)

- [ ] Routes: `/`, `/entry`, `/login`, `/role-select`, `/track`,
      `/track/result`, `/manager/...`, `/photographer/...`, `/admin/...`,
      `/profile`, `/settings/change-password`.
- [ ] Redirect guards: unauthenticated → entry/login; disabled → blocked;
      single role → role home; multi-role → role-select.
- [ ] Role-based shell routing drives the correct bottom nav.

---

## 5. Sprint 1 — Auth & shell

- [ ] SplashScreen.
- [ ] EntryScreen — **دخول سمو** / **تتبع مشروع** (two large cards).
- [ ] LoginScreen (mock auth via `AuthRepository`).
- [ ] 🔒 Disabled user (`active:false`) cannot log in.
- [ ] Multi-role detection from `defaultRole` + `extraRoles`.
- [ ] RoleSelectionScreen (shown only when >1 role).
- [ ] `MainShellScreen` + `RoleBasedBottomNav`.
- [ ] `MoreMenuScreen` for overflow nav items.
- [ ] Profile / `SettingsScreen`.
- [ ] `ChangePasswordScreen` (UI).
- [ ] Logout flow (confirm via bottom sheet).

### Sprint 1 — Dashboards
- [ ] ManagerHomeScreen (today summary, active count, pending closures, team
      availability, latest projects, quick actions).
- [ ] PhotographerHomeScreen (active projects, today/tomorrow, pending requests,
      streak placeholder, quick actions).
- [ ] AdminDashboardScreen (basic stats).
- [~] Designer / Finance / Wedding admin / Wedding finance / Attendance /
      Personal-photo dashboards — **branded placeholders, correct nav**.

### Sprint 1 — Client tracking shell
- [ ] TrackProjectScreen (secret code entry, validation, error state).
- [ ] ClientProjectResultScreen (name, status, stage timeline + %, approved
      links only, **«جاري الإبداع ⏳»** when no link).
- [~] Client rating + thank-you message submission (later).

### Sprint 1 — Admin basic
- [ ] UsersScreen (user cards list).
- [ ] PermissionsScreen (basic permission detail view).
- [~] ReportsPlaceholderScreen.
- [~] AnnouncementsPlaceholderScreen.

---

## 6. Sprint 2 — Project management

### Projects list & details
- [ ] ManagerProjectsScreen (cards, not tables).
- [ ] PhotographerMyProjectsScreen.
- [ ] Completed projects list («المنجزة»).
- [ ] Filters: All · Active · Done · Field · Social · Pending closure.
- [ ] Search: project / client / photographer name.
- [ ] Pull-to-refresh + loading/empty/error states.
- [ ] ProjectDetailsScreen (header → stage progress → team cards → notes →
      action bar) for manager and photographer variants.

### Create & assign
- [ ] AddProjectScreen — 5-step `SumouStepForm`; auto-generate serial; status
      `active`.
- [ ] AssignPhotographersScreen (searchable photographer cards, select, capacity
      hint).
- [ ] Team/member assignment cards reflect the project team.
- [ ] ManagerTeamScreen — photographer cards with monthly capacity indicator
      (available/full, UI calculation).

### Stages
- [ ] ProjectStagesScreen + UpdateProjectStageScreen (photographer advances
      stage; generic 3/7-stage engine).
- [ ] `SumouProgressTimeline` renders the correct workflow per photo type.

### Closure lifecycle
- [ ] SubmitClosureRequestScreen (report file placeholder + delivery link →
      creates pending closure request notification).
- [ ] ManagerRequestsScreen + ClosureRequestsScreen (list pending requests).
- [ ] Approve closure → project `done` (bottom sheet, green).
- [ ] Reject closure → reason captured, project stays `active` (bottom sheet,
      red).
- [ ] NotificationsScreen (basic list).
- [~] Auto payment-request generation to finance on approval (later).

---

## 7. Cross-cutting quality gates

- [ ] All async screens: loading + empty + error states.
- [ ] All lists: pull-to-refresh + search/filter where specified.
- [ ] Confirmations via bottom sheet; feedback via snackbar/toast.
- [ ] Permission-gated actions hidden when not allowed.
- [ ] RTL verified on every screen; Arabic labels and dates.
- [ ] Responsive across phone sizes; safe areas respected.
- [ ] 🔒 No hardcoded secrets / API keys; mock creds clearly mock.

---

## 8. Placeholders for later (do NOT implement now)

Provide nav entry + stub screen only:

- [~] Rekaz integration (backend-only key handling).
- [~] Full wedding system (assign → upload → approve → finance).
- [~] Push notifications (FCM).
- [~] GPS attendance / check-in.
- [~] Finance transfer flow (payment requests, receipts).
- [~] Advanced reports.
- [~] Advanced calendar.
- [~] Full file uploads (Supabase Storage).
- [~] App Store / Play Store deployment.
- [~] Full client delivery-link approval flow.
- [~] Photographer broadcast-request realtime fan-out.

---

## 9. Acceptance check (run before calling Sprint 1+2 done)

- [ ] App runs on iOS + Android emulators.
- [ ] RTL correct everywhere; no sidebar; no desktop tables in core flows.
- [ ] Mock login works; multi-role selection works; nav changes per role.
- [ ] Manager: view projects, create project, assign photographers.
- [ ] Photographer: view assigned projects, update stages, submit closure.
- [ ] Manager: approve/reject closure.
- [ ] Admin: basic user list + permission detail.
- [ ] Client tracking shell resolves a code to a status view.
- [ ] Brand colors applied; code organized; 🔒 no secrets committed.
