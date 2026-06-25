> ⛔ **Permanent Out of Scope (overrides this spec):** the **finance**
> module/transfer/payment/reports, **Rekaz** configuration/integration, and
> **notifications** (logic, in-app, push, FCM, `NotificationRepository`
> implementation) are **permanently out of scope** for all sprints unless the
> project owner explicitly requests them. Wherever this spec describes those
> features or side-effects, they are **documented-but-not-to-be-built**. The
> **Permanent Out of Scope** section in `CLAUDE.md` is authoritative.

You are Claude code acting as a senior Flutter mobile architect and product-focused UI/UX engineer.

I have an existing full HTML/JavaScript prototype for the Sumou Creative internal management system. The HTML file contains the full business logic, roles, permissions, user flows, page structure, brand identity, colors, Arabic RTL behavior, and current web experience.

Your job is NOT to copy the HTML layout directly.

Your job is to rebuild this system as a clean, production-ready, mobile-first Flutter application.

Project name:
Sumou Mobile App

Main goal:
Build a native Flutter mobile app for Sumou Creative for Visual Production. The app is used internally by staff such as project managers, photographers, designers, finance, wedding admin, attendance/admin users, and also includes a client project tracking entry using a secret project code.

Use the HTML file as the source of truth for:

* Business logic
* Roles and permissions
* Navigation structure
* Page names
* Workflows
* Statuses
* Data models
* UI states
* Brand colors
* Arabic labels
* RTL behavior
* User experience intent

But redesign everything to fit mobile users.

Do not create a web-like Flutter app.
Do not use sidebar/table-heavy layouts on mobile.
Do not directly translate HTML/CSS into Flutter widgets.
Do not expose demo passwords, API keys, or sensitive keys from the HTML in production code.
Do not hardcode secrets inside the Flutter app.

Important product direction:
The current web prototype is wide-screen and uses sidebar navigation, tables, grids, modals, and desktop-style flows. The Flutter app must use mobile UX patterns:

* Bottom navigation
* AppBar
* Role-based navigation
* Cards instead of tables
* Bottom sheets instead of small web modals
* Full-screen forms instead of complex modal forms
* Step-by-step forms for long workflows
* Compact dashboard cards
* Clear tap actions
* RTL-first Arabic interface
* Smooth mobile spacing
* Large touch targets
* Simple user journeys

Tech stack:

* Flutter
* Dart
* Supabase/PostgreSQL as backend/database layer
* Supabase Auth or a secure custom auth abstraction
* Supabase Storage for uploaded files later
* Firebase Cloud Messaging later for notifications
* RTL Arabic-first UI
* English support can be prepared but Arabic is primary
* Use clean reusable components
* Use scalable folder structure
* Use environment variables/configuration for external keys
* Use repository/service layer, not direct database calls from UI widgets

Recommended Flutter packages:

* flutter_riverpod or provider for state management
* go_router for routing
* supabase_flutter for Supabase integration
* intl for dates/language formatting
* table_calendar only if needed for mobile calendar
* flutter_svg if logo assets are SVG
* image_picker/file_picker later for upload flows
* shared_preferences only for local lightweight session/preferences, not main data

Architecture:
Use a clean, maintainable structure.

Suggested folders:

lib/
main.dart
app/
app.dart
router.dart
theme/
app_theme.dart
app_colors.dart
app_text_styles.dart
localization/
app_strings.dart
core/
constants/
utils/
widgets/
models/
services/
features/
auth/
data/
models/
providers/
screens/
widgets/
role_selection/
dashboard/
projects/
photographers/
permissions/
client_tracking/
calendar/
requests/
profile/
notifications/
admin/
wedding/
finance/
attendance/
design/
data/
repositories/
mock/
supabase/

Start with Sprint 1 + Sprint 2 scope.

Sprint 1: Core Foundation / MVP Base
Must implement:

1. Flutter app setup
2. App theme using Sumou identity
3. RTL-first Arabic layout
4. Splash screen
5. Entry screen

   * دخول سمو
   * تتبع مشروع
6. Login screen
7. Secure auth abstraction
8. User model
9. Role model
10. Permission model
11. Multi-role detection
12. Role selection screen
13. Role-based routing
14. Bottom navigation shell
15. Reusable AppBar
16. Reusable cards, badges, buttons, status chips
17. Basic dashboard layout for each role
18. Profile/settings page
19. Change password UI
20. Logout flow

Sprint 2: Basic Project Management
Must implement:

1. Projects list
2. Project details page
3. Create project flow
4. Assign photographers flow
5. Basic project stages
6. Basic closure request
7. Manager approve/reject closure request
8. Photographer “My Projects”
9. Completed projects list
10. Basic search/filter
11. Basic project status chips
12. Basic team/member assignment cards

Do not implement these fully yet, but prepare placeholders and navigation structure for later:

* Rekaz integration
* Full wedding system
* Push notifications
* GPS attendance
* Finance transfer flow
* Advanced reports
* Advanced calendar
* Full file uploads
* App Store deployment
* Full client delivery links approval flow

Brand identity:
Use these colors from the HTML:

* Background dark: #152127
* Primary teal: #215C66
* Accent green: #A7CF5B
* Green dark: #8AAE40
* Error/red: #F0524B
* Surface: #1E2E35
* Surface secondary: #243840
* Text white: #FFFFFF
* Muted text: rgba(203,202,212,0.6)
* Border: rgba(203,202,212,0.15)
* Wedding pink: #E8A0B0
* Finance yellow: #F5C842
* Designer coral: #F07080
* Photographer purple: #B87AF5
* Project blue/teal: #7FD4E0

Typography:

* Primary Arabic font should be Alexandria if available.
* If not available in Flutter, use a close Arabic-friendly font.
* Keep Arabic RTL as the primary interface.
* All text alignment should respect RTL.
* Avoid small unreadable text on mobile.
* Use clear section titles and strong hierarchy.

Mobile navigation rules:
Do not use the web sidebar as-is.
Convert web navigation into mobile role-based navigation.

Entry flow:

1. Splash
2. Entry screen:

   * دخول سمو
   * تتبع مشروع
3. Employee login
4. If user has one role, route directly
5. If user has multiple roles, show role selection
6. Route to selected role dashboard

Client tracking flow:

1. User selects “تتبع مشروع”
2. Enters secret project code
3. App shows project status
4. Shows approved links only
5. If no link uploaded, show “جاري الإبداع ⏳”
6. Client can submit rating/message later

Roles:
Create role enum or model for:

* admin
* manager
* photographer
* designer
* finance
* wedding_admin
* wedding_finance
* attendance
* personal_photo
* client_tracking

Permissions:
Create a flexible permissions system.
Each user can have:

* id
* name
* username
* active/inactive
* defaultRole
* extraRoles
* photoTypes
* feature permissions

Feature permissions:

* canAddProject
* canEditProject
* canAssignPhotographers
* canRequestPhotographer
* canRequestDesign
* canUpdateStages
* canRequestClosure
* canApproveClosure
* canManageUsers
* canManagePermissions
* canViewReports
* canManageAttendance
* canManageWeddingProjects
* canManageFinance

Important behavior:

* Disabled user cannot log in.
* User with one role enters directly.
* User with multiple roles must choose role.
* Role affects bottom nav items, available pages, and actions.
* Do not show actions that user does not have permission for.

Mobile role-based navigation:

Manager bottom nav:

1. الرئيسية
2. المشاريع
3. الطلبات
4. الفريق
5. المزيد

Photographer bottom nav:

1. الرئيسية
2. مشاريعي
3. تقويمي
4. الطلبات
5. صفحتي

Admin bottom nav:

1. لوحة التحكم
2. المستخدمين
3. الصلاحيات
4. التقارير
5. المزيد

Designer bottom nav:

1. الرئيسية
2. طلبات التصميم
3. التصاميم المنجزة
4. صفحتي

Finance bottom nav:

1. الرئيسية
2. طلبات التحويل
3. المشاريع المحولة
4. التقارير
5. صفحتي

Wedding Admin bottom nav:

1. الرئيسية
2. طلبات ركاز
3. الزواجات
4. التقويم
5. المزيد

Wedding Finance bottom nav:

1. الرئيسية
2. طلبات التحويل
3. الأرشيف
4. صفحتي

Attendance/Admin bottom nav:

1. تسجيل الحضور
2. سجلاتي
3. الجداول
4. التقارير

Personal Photography bottom nav:

1. الرئيسية
2. الحجوزات
3. التقويم
4. إضافة حجز
5. صفحتي

For Sprint 1 + Sprint 2, fully implement:

* Manager navigation
* Photographer navigation
* Admin basic navigation
* Client tracking entry shell

Other role pages can be placeholders with correct navigation and design.

Core screens to create:

Auth:

* SplashScreen
* EntryScreen
* LoginScreen
* RoleSelectionScreen

Shared shell:

* MainShellScreen
* RoleBasedBottomNav
* AppHeader
* MoreMenuScreen

Manager:

* ManagerHomeScreen
* ManagerProjectsScreen
* ManagerRequestsScreen
* ManagerTeamScreen
* ManagerMoreScreen
* AddProjectScreen
* ProjectDetailsScreen
* AssignPhotographersScreen
* ProjectStagesScreen
* ClosureRequestsScreen

Photographer:

* PhotographerHomeScreen
* PhotographerMyProjectsScreen
* PhotographerCalendarScreen
* PhotographerRequestsScreen
* PhotographerProfileScreen
* PhotographerProjectDetailsScreen
* SubmitClosureRequestScreen
* UpdateProjectStageScreen

Admin:

* AdminDashboardScreen
* UsersScreen
* PermissionsScreen
* ReportsPlaceholderScreen
* AnnouncementsPlaceholderScreen

Client tracking:

* TrackProjectScreen
* ClientProjectResultScreen

Shared pages:

* NotificationsScreen
* ChangePasswordScreen
* SettingsScreen
* EmptyStateScreen
* ErrorStateScreen

Mobile UX transformation rules:

1. Tables become cards.
   For projects, never show desktop tables.
   Use project cards with:

* Project name
* Client name
* Project type
* Date range
* Current status
* Current stage
* Assigned photographers avatars/chips
* Quick action button

2. Modals become bottom sheets or full screens.
   Small confirmation actions:

* bottom sheet

Long forms:

* full screen page

Complex add project:

* multi-step form:
  Step 1: Project basic info
  Step 2: Client/date info
  Step 3: Assign manager
  Step 4: Add photographers/roles
  Step 5: Notes and review
  Save

3. Web grid dashboards become horizontal/vertical mobile cards.
   Use 2-column stat cards when screen allows, otherwise stacked.

4. Calendar should be mobile-friendly.
   Use a compact calendar with agenda list below.
   Avoid full desktop month grid with tiny event labels.

5. Actions should be clear.
   Use one main CTA per screen.
   Secondary actions can be inside overflow menu or bottom sheet.

6. RTL must be native.
   Use Directionality(textDirection: TextDirection.rtl).
   All Arabic screens should align right.
   Bottom navigation labels Arabic.
   Use Arabic date formatting where possible.

7. Status badges:
   Use consistent status chips:

* نشط
* منتهي
* بانتظار الموافقة
* مرفوض
* مقبول
* قيد التنفيذ
* جاري الإبداع
* تم التسليم

Data models to create:

UserModel:

* id
* fullName
* username
* email optional
* avatarInitials
* active
* defaultRole
* roles
* photoTypes
* permissions

RoleModel:

* id
* nameAr
* nameEn
* type
* color
* icon

PermissionModel:

* userId
* active
* roles
* photoTypes
* features

ProjectModel:

* id
* serial
* name
* clientName
* managerId
* managerName
* startDate
* endDate
* status
* type: field/social/wedding
* notes
* teamRoles
* currentStage
* stages
* createdAt
* updatedAt

ProjectTeamRole:

* id
* projectId
* type
* userId
* personName
* photographerId
* value
* date

ProjectStageModel:

* id
* projectId
* title
* order
* status
* notes
* updatedBy
* updatedAt

ClosureRequestModel:

* id
* projectId
* projectName
* submittedBy
* submittedByName
* reportFileUrl optional
* deliveryLink optional
* status: pending/approved/rejected
* rejectReason optional
* createdAt
* reviewedAt

PhotoRequestModel:

* id
* projectId
* projectName
* requestedBy
* type
* date
* value
* status
* candidates
* acceptedBy
* notes

NotificationModel:

* id
* userId
* title
* body
* type
* isRead
* createdAt
* relatedId

ClientTrackingModel:

* serial
* projectName
* clientName
* status
* approvedLinks
* message
* rating

Project types:

* field
* social
* wedding

Photography types:

* مصور فوتوغرافي
* مصور فيديو
* درون
* بث مباشر
* منتجات
* هوائي
* مونتاج
* إضاءة
* مساعد مصور
* كواليس
* انستقرام
* تيك توك
* وحدة نشر

Project stages:
For simple 3-stage flow:

1. استلام الأوردر
2. في رحلة الإبداع
3. تم التسليم

For social/marketing 7-stage flow:

1. استلام الأوردر
2. الاجتماع مع العميل
3. كتابة الخطة
4. رحلة الإبداع
5. رحلة التعديل
6. التسليم
7. النشر

For Sprint 2:
Implement stage UI generically so it can support both 3-stage and 7-stage workflows.

Project details mobile page:
Top section:

* Project title
* Status chip
* Client name
* Date range
* Project type

Middle:

* Current stage progress
* Assigned team cards
* Notes

Actions:

* Update stage
* Request closure
* Assign photographer
* Approve/reject closure if manager
* View delivery link if available

Manager home:
Show:

* Today summary
* Active projects count
* Pending closure requests count
* Team availability summary
* Latest projects
* Quick actions:

  * Add project
  * View requests
  * View team

Photographer home:
Show:

* My active projects
* Today/tomorrow schedule
* Pending requests
* Current streak/summary placeholder
* Quick actions:

  * Update stage
  * Submit closure

Projects list:
Filters:

* All
* Active
* Done
* Field
* Social
* Pending closure

Search:

* Project name
* Client name
* Photographer name

Card actions:

* Tap card to open details
* Long press or overflow for quick actions

Team screen:
Use photographer cards:

* Name
* Photo types
* Active projects count
* Monthly capacity indicator
* Status available/full
* Tap to view profile/details

Capacity:
For now implement UI-only or simple calculation:

* Count active projects per photographer in current month
* If full, show red/full status
* Disable assigning if capacity reached later

Permissions UI:
Admin can view users and permissions.
For Sprint 1, build basic user list and permission details UI.
Advanced editing can be prepared but not fully complex.

Security:
The HTML contains demo accounts and keys.
Do not use them as production credentials.
Do not commit API keys.
Do not expose Rekaz API key in Flutter.
Use environment config for any API keys.
Any Rekaz integration must later be done through backend/serverless function, not directly from mobile.

Backend strategy:
Create repository interfaces first:

* AuthRepository
* UserRepository
* ProjectRepository
* PermissionRepository
* NotificationRepository
* TrackingRepository

For first implementation:

* Use mock data or local in-memory data if Supabase schema is not ready.
* Keep repositories ready to connect to Supabase.
* Do not mix UI widgets with backend query logic.

Supabase tables to prepare later:

* users
* roles
* user_roles
* user_permissions
* photographer_types
* projects
* project_team
* project_stages
* closure_requests
* photo_requests
* notifications
* client_reviews
* project_links

Design system components to create:

* SumouScaffold
* SumouAppBar
* SumouBottomNav
* SumouCard
* SumouButton
* SumouTextField
* SumouDropdown
* SumouStatusChip
* SumouStatCard
* SumouProjectCard
* SumouUserCard
* SumouSectionHeader
* SumouEmptyState
* SumouBottomSheet
* SumouStepForm
* SumouProgressTimeline

Design requirements:

* Use dark background #152127
* Use cards with #1E2E35 or #243840
* Use green #A7CF5B for primary CTAs
* Use teal #215C66 for primary brand elements
* Use red #F0524B for errors/rejections
* Use subtle borders
* Use rounded corners 12–18px
* Use generous padding
* Use safe areas
* Make all touch targets at least 44px high
* Avoid dense text
* Avoid desktop tables
* Use icons where helpful
* Keep UI premium, simple, and operational

Important UI behavior:

* Loading states for all async screens
* Empty states for no projects/requests
* Error states for failed fetch/auth
* Pull to refresh on list screens
* Search and filter on project/team lists
* Bottom sheet for confirmation
* Snackbar/toast for success/error

Routing:
Use go_router.

Suggested routes:
/
/entry
/login
/role-select
/track
/track/result
/manager/home
/manager/projects
/manager/projects/add
/manager/projects/
/manager/projects//assign
/manager/requests
/manager/team
/photographer/home
/photographer/projects
/photographer/projects/
/photographer/calendar
/photographer/requests
/admin/home
/admin/users
/admin/permissions
/profile
/settings/change-password

Implementation priority:

1. Build theme and design system
2. Build mock models and data
3. Build auth/entry/role selection
4. Build role-based shell and bottom nav
5. Build manager dashboard
6. Build project list and project cards
7. Build project details
8. Build add project flow
9. Build assign photographer flow
10. Build photographer my projects
11. Build stages UI
12. Build closure request UI
13. Build manager approval/rejection UI
14. Build admin users/permissions basic UI
15. Prepare placeholders for later modules

Acceptance criteria:

* App runs on iOS and Android emulator
* Arabic RTL is correct across screens
* Mobile layout is not copied from web
* No sidebar used on mobile
* No desktop tables for core mobile flows
* User can login using mock auth
* User with multiple roles can choose a role
* Navigation changes based on selected role
* Manager can view projects
* Manager can create basic project
* Manager can assign photographers
* Photographer can view assigned projects
* Photographer can update stages
* Photographer can submit closure request
* Manager can approve/reject closure request
* UI follows Sumou brand colors
* Code is organized and maintainable
* No sensitive API keys are hardcoded
* Screens are responsive to different mobile sizes

Important:
The uploaded HTML is the reference, not the final structure.
Keep the logic and workflows, but improve the experience for mobile users.
When there is a conflict between web layout and mobile usability, choose mobile usability.
Build the app as if it will be used daily by staff on phones during real work.

Start by scanning the existing HTML file and extracting:

1. Roles
2. Navigation items
3. Screens
4. Permissions
5. Workflows
6. Colors
7. Data entities
8. Current UI states

Then implement the Flutter app using the mobile-first plan above.
