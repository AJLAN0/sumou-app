-- =============================================================================
-- Sprint 9 · Step 2 — Identity & Access schema
-- Domain: profiles, roles, user_roles, permissions, role_permissions,
--         user_permissions, audit_logs (+ generic updated_at helper).
--
-- Frozen decisions applied (see docs/SUPABASE_CORE_PLAN.md §1):
--   D1 roles as a lookup table (not an enum), incl. real `marketing` role
--   D2 username-based identity; internal auth email lives on auth.users (never
--      stored on profiles / never user-facing)
--   D5 normalized permissions: permissions + role_permissions (defaults) +
--      user_permissions (overrides) — NOT jsonb
--   D6 soft delete on profiles (is_active/deleted_at/deleted_by); audit_logs
--      is retained operational history (no delete)
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): this migration creates NO working
-- tables, grants, RLS, RPCs, or logic for finance, payments, Rekaz,
-- notifications, FCM, push, or reminders. The finance role codes and the
-- `can_manage_finance` permission are kept ONLY as inert, INACTIVE catalog
-- placeholders (is_active = false) for future compatibility — never granted,
-- never assigned, zero operational behavior.
--
-- RLS: enabled on every table below with NO policies yet → access is DENIED for
-- anon and authenticated roles until Sprint 9 Step 6 adds the policy set. These
-- tables are never publicly readable.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Generic helper: maintain updated_at on UPDATE. Schema-qualified, empty
-- search_path. (No role-resolution / RLS helpers here — those belong to Step 6.)
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- roles (D1) — lookup of stable role codes.
-- ---------------------------------------------------------------------------
create table public.roles (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name_ar    text not null,
  is_active  boolean not null default true,
  constraint roles_code_format_chk check (code ~ '^[a-z][a-z_]*$'),
  constraint roles_name_ar_not_blank_chk check (char_length(btrim(name_ar)) > 0)
);
comment on table public.roles is
  'Role catalog (lookup, not an enum). Codes mirror Flutter RoleType keys plus the marketing role.';

-- ---------------------------------------------------------------------------
-- permissions (D5) — normalized feature catalog. `is_active` lets excluded
-- codes (can_manage_finance) exist as inert reserved placeholders, never granted.
-- ---------------------------------------------------------------------------
create table public.permissions (
  id        uuid primary key default gen_random_uuid(),
  code      text not null unique,
  name_ar   text not null,
  is_active boolean not null default true,
  constraint permissions_code_format_chk check (code ~ '^[a-z][a-z_]*$'),
  constraint permissions_name_ar_not_blank_chk check (char_length(btrim(name_ar)) > 0)
);
comment on table public.permissions is
  'Feature-permission catalog (normalized). Inactive rows (is_active=false) are inert reserved placeholders, never granted (e.g. can_manage_finance).';

-- ---------------------------------------------------------------------------
-- profiles (D2, D6) — staff identity, 1:1 with auth.users.
-- The internal generated auth email is NOT stored here (it lives on
-- auth.users and is never user-facing).
-- ---------------------------------------------------------------------------
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  username         text not null unique,
  full_name        text not null,
  default_role_id  uuid not null references public.roles (id),
  avatar_initials  text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  deleted_by       uuid references public.profiles (id),
  -- Normalized username: lowercase, trimmed, no spaces, non-blank (D2).
  constraint profiles_username_format_chk check (username ~ '^[a-z0-9._-]{2,50}$'),
  constraint profiles_full_name_not_blank_chk check (char_length(btrim(full_name)) > 0)
);
comment on table public.profiles is
  'Staff identity, 1:1 with auth.users. Internal auth email is never stored here (D2).';
comment on column public.profiles.username is
  'Unique normalized handle (lowercase, trimmed, [a-z0-9._-], 2..50). Used for login.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- user_roles (D1) — many-to-many profiles <-> roles. PK prevents duplicates.
-- ---------------------------------------------------------------------------
create table public.user_roles (
  user_id uuid not null references public.profiles (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete restrict,
  primary key (user_id, role_id)
);
comment on table public.user_roles is
  'Roles held by a user. A user''s default_role_id must be one of these rows.';

-- Default-role invariant (safest DB-level enforcement): a profile's default
-- role must be a role the user actually holds. Composite FK to user_roles,
-- DEFERRABLE so profile + its default user_role can be inserted in one txn.
alter table public.profiles
  add constraint profiles_default_role_in_user_roles_fk
  foreign key (id, default_role_id)
  references public.user_roles (user_id, role_id)
  deferrable initially deferred;

-- ---------------------------------------------------------------------------
-- role_permissions (D5) — per-role default grants. PK prevents duplicates.
-- ---------------------------------------------------------------------------
create table public.role_permissions (
  role_id       uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  granted       boolean not null default true,
  primary key (role_id, permission_id)
);
comment on table public.role_permissions is
  'Role DEFAULT permissions. Effective access = user override if present, else OR of these.';

-- ---------------------------------------------------------------------------
-- user_permissions (D5) — per-user overrides. `granted` is explicit (no
-- default) so a row always means an intentional override, never a role default.
-- PK prevents duplicate overrides for the same (user, permission).
-- ---------------------------------------------------------------------------
create table public.user_permissions (
  user_id       uuid not null references public.profiles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  granted       boolean not null,
  primary key (user_id, permission_id)
);
comment on table public.user_permissions is
  'User-specific permission OVERRIDES (granted set explicitly). Distinct from role defaults.';

-- ---------------------------------------------------------------------------
-- audit_logs (D6) — retained operational history. No delete. Never log
-- passwords, tokens, internal auth emails, or secrets.
-- ---------------------------------------------------------------------------
create table public.audit_logs (
  id         uuid primary key default gen_random_uuid(),
  actor_id   uuid references public.profiles (id) on delete set null,
  action     text not null,
  entity     text,
  entity_id  uuid,
  meta       jsonb,
  created_at timestamptz not null default now(),
  constraint audit_logs_action_not_blank_chk check (char_length(btrim(action)) > 0)
);
comment on table public.audit_logs is
  'Immutable operational history. Never store passwords, tokens, internal auth emails, or secrets in meta.';

-- ---------------------------------------------------------------------------
-- Indexes (PKs/uniques already index their columns).
-- ---------------------------------------------------------------------------
create index profiles_default_role_id_idx on public.profiles (default_role_id);
create index user_roles_role_id_idx       on public.user_roles (role_id);
create index role_permissions_perm_idx    on public.role_permissions (permission_id);
create index user_permissions_perm_idx    on public.user_permissions (permission_id);
create index audit_logs_actor_idx         on public.audit_logs (actor_id);
create index audit_logs_entity_idx        on public.audit_logs (entity, entity_id);
create index audit_logs_created_at_idx    on public.audit_logs (created_at);

-- ---------------------------------------------------------------------------
-- Reference catalog data (required, idempotent). Roles + permissions + role
-- defaults only. NO users, NO auth accounts, NO passwords, NO project data.
-- ---------------------------------------------------------------------------

-- Roles: Flutter RoleType keys + name_ar, plus `marketing` (D1).
-- `finance`/`wedding_finance` are kept as INACTIVE reserved placeholders
-- (is_active=false) — inert legacy codes, never granted/assigned (guardrail).
-- `client_tracking` is intentionally NOT a staff role — public client tracking
-- is anonymous (no profile). `marketing` name_ar is provisional ('تسويق') until
-- the Flutter RoleType adds it (see Step 2 report).
insert into public.roles (code, name_ar, is_active) values
  ('admin',           'الإدارة',        true),
  ('manager',         'مدير مشاريع',    true),
  ('photographer',    'مصور',           true),
  ('marketing',       'تسويق',          true),
  ('designer',        'مصمم',           true),
  ('wedding_admin',   'إدارة الزواجات', true),
  ('attendance',      'تسجيل الحضور',   true),
  ('personal_photo',  'التصوير الشخصي', true),
  ('finance',         'مالية سمو',      false),
  ('wedding_finance', 'مالية الزواجات', false)
on conflict (code) do update set name_ar = excluded.name_ar, is_active = excluded.is_active;

-- Permissions: AppFeature codes (name_ar from featureLabelAr). These 13 are
-- active/grantable. can_manage_finance is inserted separately (inactive).
insert into public.permissions (code, name_ar) values
  ('can_add_project',            'إضافة مشروع'),
  ('can_edit_project',           'تعديل مشروع'),
  ('can_assign_photographers',   'إسناد مصورين'),
  ('can_request_photographer',   'طلب مصور'),
  ('can_request_design',         'طلب تصميم'),
  ('can_update_stages',          'تحديث المراحل'),
  ('can_request_closure',        'طلب إغلاق'),
  ('can_approve_closure',        'اعتماد الإغلاق'),
  ('can_manage_users',           'إدارة المستخدمين'),
  ('can_manage_permissions',     'إدارة الصلاحيات'),
  ('can_view_reports',           'عرض التقارير'),
  ('can_manage_attendance',      'إدارة الحضور'),
  ('can_manage_wedding_projects','إدارة الزواجات')
on conflict (code) do update set name_ar = excluded.name_ar;

-- Inert reserved placeholder for future compatibility (guardrail): kept in the
-- catalog but INACTIVE — never granted (see role_permissions), never assigned,
-- zero operational behavior. Finance stays permanently out of scope functionally.
insert into public.permissions (code, name_ar, is_active) values
  ('can_manage_finance', 'إدارة المالية', false)
on conflict (code) do update set name_ar = excluded.name_ar, is_active = excluded.is_active;

-- Role default permissions, mirroring FeaturePermissions.defaultsFor.
-- Inert roles (finance, wedding_finance) and roles without defined defaults
-- (marketing, designer, personal_photo) get NO defaults seeded. The inactive
-- finance roles and the inactive can_manage_finance permission are NEVER granted
-- here — zero operational behavior (guardrail).
insert into public.role_permissions (role_id, permission_id, granted)
select r.id, p.id, true
from (values
  ('admin',         'can_manage_users'),
  ('admin',         'can_manage_permissions'),
  ('admin',         'can_view_reports'),
  ('manager',       'can_add_project'),
  ('manager',       'can_edit_project'),
  ('manager',       'can_assign_photographers'),
  ('manager',       'can_update_stages'),
  ('manager',       'can_approve_closure'),
  ('manager',       'can_view_reports'),
  ('photographer',  'can_request_photographer'),
  ('photographer',  'can_request_design'),
  ('photographer',  'can_update_stages'),
  ('photographer',  'can_request_closure'),
  ('wedding_admin', 'can_add_project'),
  ('wedding_admin', 'can_assign_photographers'),
  ('wedding_admin', 'can_manage_wedding_projects'),
  ('attendance',    'can_manage_attendance')
) as d(role_code, perm_code)
join public.roles r       on r.code = d.role_code
join public.permissions p on p.code = d.perm_code
on conflict (role_id, permission_id) do nothing;

-- ---------------------------------------------------------------------------
-- Enable RLS on every table (default-deny). NO policies yet → anon and
-- authenticated have NO access until Sprint 9 Step 6 adds policies. Migration
-- runs as table owner (bypasses RLS), so the seeds above still apply.
-- ---------------------------------------------------------------------------
alter table public.roles            enable row level security;
alter table public.permissions      enable row level security;
alter table public.profiles         enable row level security;
alter table public.user_roles       enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_permissions enable row level security;
alter table public.audit_logs       enable row level security;
