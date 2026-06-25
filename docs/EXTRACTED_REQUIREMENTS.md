# Sumou Mobile App — Extracted Requirements

> **Source of truth:** `docs/MASTER_SPEC.md` + the web prototype in
> `docs/reference/` (`sumou_app (10).html` business logic, `sumou_docs (6).html`
> documentation). The HTML is a reference for **logic and workflows**, not for
> layout. The Flutter app is **mobile-first, Arabic RTL, and role-based**.
>
> This document captures **what the system must do**. Scope sequencing lives in
> `SPRINT_PLAN.md`; UI translation rules live in `MOBILE_UX_TRANSFORMATION.md`;
> the build task list lives in `IMPLEMENTATION_CHECKLIST.md`.
>
> ⛔ **Permanent Out of Scope (overrides this document):** the **finance**
> module/transfer/payment/reports, **Rekaz** configuration/integration, and
> **notifications** (logic, in-app, push, FCM, `NotificationRepository`
> implementation) are **permanently out of scope** for all sprints unless the
> project owner explicitly requests them. Where this document describes those
> features, related models, or notification side-effects (e.g. closure →
> notification, approval → finance payment, `NotificationModel` "Sprint 2"),
> treat them as **documented-but-not-to-be-built**. See the **Permanent Out of
> Scope** section in `CLAUDE.md` (authoritative).

---

## 1. Roles

Ten roles exist in the system. Each user has one `defaultRole` and optional
`extraRoles`.

| # | Role enum | Arabic label | Accent color | Sprint 1–2 status |
|---|-----------|--------------|--------------|-------------------|
| 1 | `admin` | الإدارة / لوحة التحكم | project teal `#7FD4E0` | **Basic (in scope)** |
| 2 | `manager` | مدير مشاريع | teal `#215C66` | **Full (in scope)** |
| 3 | `photographer` | مصور | purple `#B87AF5` | **Full (in scope)** |
| 4 | `designer` | مصمم | coral `#F07080` | Placeholder |
| 5 | `finance` (`accountant`) | مالية سمو | yellow `#F5C842` | Placeholder |
| 6 | `wedding_admin` | إدارة الزواجات | pink `#E8A0B0` | Placeholder |
| 7 | `wedding_finance` | مالية الزواجات | yellow `#F5C842` | Placeholder |
| 8 | `attendance` | تسجيل الحضور | — | Placeholder |
| 9 | `personal_photo` | التصوير الشخصي | — | Placeholder |
| 10 | `client_tracking` | تتبع مشروع (no login) | green `#A7CF5B` | **Entry shell (in scope)** |

**Role behavior rules (from prototype):**
- A disabled user (`active: false`) **cannot log in**.
- A user with a **single role** routes directly to that role's dashboard.
- A user with **multiple roles** (`defaultRole` + `extraRoles`) must pick a role
  on the Role Selection screen before entering.
- The selected role determines **bottom-nav items, available screens, and
  visible actions**.
- `client_tracking` is **not** an authenticated role — it is a public entry that
  takes a secret project code, no username/password.

---

## 2. Permissions

Permissions are a two-layer system stored per user.

### 2a. Feature permissions (boolean flags)
| Flag | Meaning | Sprint 1–2 enforced? |
|------|---------|----------------------|
| `canAddProject` | Create a project | ✅ |
| `canEditProject` | Edit a project | ✅ |
| `canAssignPhotographers` | Assign team to a project | ✅ |
| `canRequestPhotographer` | Broadcast a photographer request | Placeholder |
| `canRequestDesign` | Send a design request | Placeholder |
| `canUpdateStages` | Advance project stages | ✅ |
| `canRequestClosure` | Submit a closure request | ✅ |
| `canApproveClosure` | Approve/reject closure | ✅ |
| `canManageUsers` | Create/edit users | ✅ (basic, admin) |
| `canManagePermissions` | Edit user permissions | ✅ (basic, admin) |
| `canViewReports` | View reports | Placeholder |
| `canManageAttendance` | Attendance admin | Placeholder |
| `canManageWeddingProjects` | Wedding admin | Placeholder |
| `canManageFinance` | Finance flows | Placeholder |

### 2b. Default feature sets per role (from prototype `getDefaultFeatures`)
| Role | addProject | updateStages | requestClosure | requestPhotographer | requestDesign |
|------|:--:|:--:|:--:|:--:|:--:|
| manager | ✅ | ✅ | ✅ (approve) | — | — |
| photographer | — | ✅ | ✅ (submit) | ✅ | ✅ |
| designer | — | — | — | — | — |
| finance | — | — | — | — | — |
| wedding_admin | ✅ | — | — | — | — |
| wedding_finance | — | — | — | — | — |
| attendance | — | — | — | — | — |

### 2c. Photo-type permissions (photographers only)
When a user's roles include `photographer`, they carry one or more **photo
types**. Each photo type has a config (`PHOTO_TYPE_CONFIG` in the prototype):
- `canReceiveRequests` — eligible to receive broadcast photographer requests.
- `uploadLinks` — which deliverable links apply (`photos`, `raw`, `video`).
- `canClose` — may submit a closure request.
- `stages` — **which stage workflow applies** (3-stage vs 7-stage; see §5).

> **Rule:** never show an action the current user lacks permission for. Hide it,
> don't just disable it (disable only when capacity/state blocks it temporarily).

---

## 3. Navigation items (mobile bottom nav)

Per `MASTER_SPEC.md`. The web prototype's sidebar items that don't fit five
tabs (e.g. «المنجزة», «الأيام الخاصة») move into the **More** menu, not the bar.

**In scope now (fully built):**
- **Manager:** الرئيسية · المشاريع · الطلبات · الفريق · المزيد
- **Photographer:** الرئيسية · مشاريعي · تقويمي · الطلبات · صفحتي
- **Admin (basic):** لوحة التحكم · المستخدمين · الصلاحيات · التقارير · المزيد

**Placeholder (correct nav + design, screens stubbed):**
- **Designer:** الرئيسية · طلبات التصميم · التصاميم المنجزة · صفحتي
- **Finance:** الرئيسية · طلبات التحويل · المشاريع المحولة · التقارير · صفحتي
- **Wedding Admin:** الرئيسية · طلبات ركاز · الزواجات · التقويم · المزيد
- **Wedding Finance:** الرئيسية · طلبات التحويل · الأرشيف · صفحتي
- **Attendance:** تسجيل الحضور · سجلاتي · الجداول · التقارير
- **Personal Photo:** الرئيسية · الحجوزات · التقويم · إضافة حجز · صفحتي

---

## 4. Screens

### Auth (Sprint 1)
SplashScreen · EntryScreen (دخول سمو / تتبع مشروع) · LoginScreen ·
RoleSelectionScreen

### Shared shell (Sprint 1)
MainShellScreen · RoleBasedBottomNav · AppHeader · MoreMenuScreen

### Manager (Sprint 1 home + Sprint 2 management)
ManagerHomeScreen · ManagerProjectsScreen · ManagerRequestsScreen ·
ManagerTeamScreen · ManagerMoreScreen · AddProjectScreen ·
ProjectDetailsScreen · AssignPhotographersScreen · ProjectStagesScreen ·
ClosureRequestsScreen

### Photographer (Sprint 1 home + Sprint 2 management)
PhotographerHomeScreen · PhotographerMyProjectsScreen ·
PhotographerCalendarScreen · PhotographerRequestsScreen ·
PhotographerProfileScreen · PhotographerProjectDetailsScreen ·
SubmitClosureRequestScreen · UpdateProjectStageScreen

### Admin (Sprint 1 basic)
AdminDashboardScreen · UsersScreen · PermissionsScreen ·
ReportsPlaceholderScreen · AnnouncementsPlaceholderScreen

### Client tracking (Sprint 1 shell)
TrackProjectScreen · ClientProjectResultScreen

### Shared utility
NotificationsScreen · ChangePasswordScreen · SettingsScreen ·
EmptyStateScreen · ErrorStateScreen

---

## 5. Workflows

### 5.1 Entry / Login (Sprint 1 — in scope)
Splash → Entry (دخول سمو / تتبع مشروع) → Login → if single role route directly;
if multiple roles → Role Selection → role dashboard. Disabled users are
rejected at login.

### 5.2 Create project (Sprint 2 — in scope)
Manager enters name, client, start/end dates, assigned manager, team roles
(each role: type + person + value), notes → app **auto-generates a secret
serial** (e.g. `X7K-29QM-4R`) → project saved with status `active`.
On mobile this becomes a **5-step form** (basic info → client/date → manager →
team roles → notes & review).

### 5.3 Project stages (Sprint 2 — in scope, generic engine)
A generic stage engine renders progress for either workflow:
- **Simple 3-stage:** استلام الأوردر → في رحلة الإبداع → تم التسليم
- **Social/marketing 7-stage:** استلام الأوردر → الاجتماع مع العميل → كتابة الخطة
  → رحلة الإبداع → رحلة التعديل → التسليم → النشر

The active workflow is chosen by the project's photo type. Photographer advances
the current stage; manager can view progress.

### 5.4 Closure request (Sprint 2 — in scope)
Photographer submits a **report file + delivery link** → creates a
`close_request` notification (status `pending`) to the project's manager →
manager **approves** (project → `done`; in full system this also spawns payment
requests to finance for paid roles — *that part is placeholder*) **or rejects**
(records a reason; project stays `active`).

### 5.5 Photographer broadcast request (Placeholder — nav + stub only)
Manager requests a photo type → request is sent to **all** photographers
registered with that type → **first to accept** wins and is added to the
project; others receive a «خيرها بغيرها 🌟» notice. Build the data shapes and
screen stub now; full realtime fan-out is later.

### 5.6 Client tracking (Sprint 1 — entry shell; full links later)
Client enters secret code → sees project name, status, **stage timeline + %**,
and **approved links only**. If no link uploaded yet → show **«جاري الإبداع ⏳»**.
Client may later submit a **rating + thank-you message** that reaches the
photographer as a positive notification. *Full delivery-link approval flow is
placeholder.*

### 5.7 Wedding flow (Placeholder — later)
Rekaz booking → wedding admin assigns photographers → photographers upload
raw/edited/live links (live appears instantly, others need admin approval) →
client sees approved links → wedding finance pays and uploads receipts. Prepare
navigation and models only.

---

## 6. Colors & brand identity

| Token | Hex / value | Use |
|-------|-------------|-----|
| Background dark | `#152127` | App background |
| Primary teal | `#215C66` | Brand elements |
| Accent green | `#A7CF5B` | Primary CTAs |
| Green dark | `#8AAE40` | CTA pressed / accents |
| Error red | `#F0524B` | Errors, rejections |
| Surface | `#1E2E35` | Cards |
| Surface secondary | `#243840` | Raised cards / inputs |
| Text white | `#FFFFFF` | Primary text |
| Muted text | `rgba(203,202,212,0.6)` | Secondary text |
| Border | `rgba(203,202,212,0.15)` | Subtle borders |
| Wedding pink | `#E8A0B0` | Wedding role accent |
| Finance yellow | `#F5C842` | Finance role accent |
| Designer coral | `#F07080` | Designer role accent |
| Photographer purple | `#B87AF5` | Photographer role accent |
| Project teal | `#7FD4E0` | Project / admin accent |

**Typography:** Alexandria (Arabic) or close Arabic-friendly fallback. RTL-first,
right-aligned text, strong hierarchy, no tiny text. **Shape:** rounded corners
12–18px, generous padding, touch targets ≥ 44px, safe areas respected.

---

## 7. Data entities

| Model | Key fields | Sprint focus |
|-------|------------|--------------|
| **UserModel** | id, fullName, username, email?, avatarInitials, active, defaultRole, roles, photoTypes, permissions | Sprint 1 |
| **RoleModel** | id, nameAr, nameEn, type, color, icon | Sprint 1 |
| **PermissionModel** | userId, active, roles, photoTypes, features | Sprint 1 |
| **ProjectModel** | id, serial, name, clientName, managerId, managerName, startDate, endDate, status, type (field/social/wedding), notes, teamRoles, currentStage, stages, createdAt, updatedAt | Sprint 2 |
| **ProjectTeamRole** | id, projectId, type, userId, personName, photographerId, value, date | Sprint 2 |
| **ProjectStageModel** | id, projectId, title, order, status, notes, updatedBy, updatedAt | Sprint 2 |
| **ClosureRequestModel** | id, projectId, projectName, submittedBy, submittedByName, reportFileUrl?, deliveryLink?, status (pending/approved/rejected), rejectReason?, createdAt, reviewedAt | Sprint 2 |
| **PhotoRequestModel** | id, projectId, projectName, requestedBy, type, date, value, status, candidates, acceptedBy, notes | Model now, flow later |
| **NotificationModel** | id, userId, title, body, type, isRead, createdAt, relatedId | Sprint 2 (basic) |
| **ClientTrackingModel** | serial, projectName, clientName, status, approvedLinks, message, rating | Sprint 1 |

**Project types:** `field` · `social` · `wedding`.

**Photography types:** مصور فوتوغرافي · مصور فيديو · درون · بث مباشر · منتجات ·
هوائي · مونتاج · إضاءة · مساعد مصور · كواليس · انستقرام · تيك توك · وحدة نشر.

**Repository interfaces (define now, mock impl first, Supabase-ready):**
AuthRepository · UserRepository · ProjectRepository · PermissionRepository ·
NotificationRepository · TrackingRepository.

**Supabase tables (prepare later):** users · roles · user_roles ·
user_permissions · photographer_types · projects · project_team ·
project_stages · closure_requests · photo_requests · notifications ·
client_reviews · project_links.

---

## 8. UI states

**Status chips (consistent vocabulary):**
نشط · منتهي · بانتظار الموافقة · مرفوض · مقبول · قيد التنفيذ · جاري الإبداع ·
تم التسليم.

**Required states on every relevant screen:**
- **Loading** state for all async screens.
- **Empty** state for no projects / requests / results.
- **Error** state for failed fetch / auth.
- **Pull-to-refresh** on list screens.
- **Search + filter** on project/team lists.
- **Bottom sheet** for confirmations.
- **Snackbar/toast** for success/error feedback.

---

## 9. Security requirements

- Demo accounts/passwords in the HTML are **not** production credentials — never
  ship them as real auth.
- **No API keys hardcoded** in the Flutter app; use environment configuration.
- The **Rekaz API key must never** live in the mobile app — any Rekaz
  integration goes through a backend/serverless function later.
- Use a secure auth **abstraction** (`AuthRepository`) so mock auth today can be
  swapped for Supabase Auth without touching UI.

---

## 10. Acceptance criteria (Sprint 1 + 2)

- App runs on iOS and Android emulators.
- Arabic RTL correct across all screens; no web sidebar; no desktop tables.
- Mock login works; multi-role users can choose a role; nav changes per role.
- Manager can view projects, create a basic project, assign photographers.
- Photographer can view assigned projects, update stages, submit closure.
- Manager can approve/reject a closure request.
- Admin can view a basic user list and permission detail.
- Client tracking entry shell resolves a code to a status view.
- UI follows Sumou brand colors; code organized/maintainable; no secrets in code.
