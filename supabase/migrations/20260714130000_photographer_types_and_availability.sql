-- =============================================================================
-- Sprint 9 · Step 3 — Photographer types & user availability
-- Domain: photographer_types, user_photographer_types, user_unavailability.
-- Runs AFTER 20260714120000_identity_and_access.sql (depends on public.profiles
-- and the public.set_updated_at() helper created there).
--
-- Frozen decisions applied (see docs/SUPABASE_CORE_PLAN.md §1 / SCHEMA_DRAFT §3):
--   D3 normalized photographer types (lookup + user relation)
--   Availability data (leave/permission periods) that the assignment rules check.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): creates NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders constructs. Leave records here have NO
-- notification or reminder behavior — they are plain availability data.
--
-- Scope: NO project or project-team tables (those are Step 4). NO assignment or
-- overlap/marketing-exemption logic (that is the later project-team RPC step).
--
-- RLS: enabled on every table below with NO policies yet → default-deny for
-- anon and authenticated until Sprint 9 Step 6. Availability is never public.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- photographer_types (D3) — normalized lookup. Free-text types are NOT the
-- primary model; this table is the source of truth.
-- ---------------------------------------------------------------------------
create table public.photographer_types (
  id        uuid primary key default gen_random_uuid(),
  code      text not null unique,
  name_ar   text not null unique,
  is_active boolean not null default true,
  constraint photographer_types_code_format_chk check (code ~ '^[a-z][a-z_]*$'),
  constraint photographer_types_name_ar_not_blank_chk check (char_length(btrim(name_ar)) > 0)
);
comment on table public.photographer_types is
  'Photographer/photo-type catalog (lookup). Codes are stable; name_ar is the Arabic display label.';

-- ---------------------------------------------------------------------------
-- user_photographer_types (D3) — a user's skills (many-to-many). PK prevents
-- duplicate (user, type) rows.
-- ---------------------------------------------------------------------------
create table public.user_photographer_types (
  user_id              uuid not null references public.profiles (id) on delete cascade,
  photographer_type_id uuid not null references public.photographer_types (id) on delete restrict,
  primary key (user_id, photographer_type_id)
);
comment on table public.user_photographer_types is
  'Photographer types a user is skilled in (M:N profiles <-> photographer_types).';

-- ---------------------------------------------------------------------------
-- user_unavailability — employee leave/permission/unavailability periods that
-- the assignment availability rules consult (replaces the mock MockLeave data).
-- Retained operational history: cancel via is_active=false, do not hard-delete.
-- NO notifications/reminders are created from these rows (guardrail).
-- ---------------------------------------------------------------------------
create table public.user_unavailability (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  -- Reason/type of the period, e.g. leave/permission (free-form for now; may
  -- become a lookup later). Distinguishes "محجوز" vs "إذن" style reasons.
  kind       text,
  notes      text,
  -- Active period, or cancelled (is_active=false). History is retained.
  is_active  boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_unavailability_range_chk check (ends_at >= starts_at)
);
comment on table public.user_unavailability is
  'Leave/permission/unavailability periods per user. Availability checks overlap these against a project date. No notifications/reminders.';

create trigger user_unavailability_set_updated_at
  before update on public.user_unavailability
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes for availability checks (by user + date/time range).
-- ---------------------------------------------------------------------------
create index user_photographer_types_type_idx
  on public.user_photographer_types (photographer_type_id);
create index user_unavailability_user_range_idx
  on public.user_unavailability (user_id, starts_at, ends_at) where is_active;

-- ---------------------------------------------------------------------------
-- Marketing rule preparation (documentation only — NO logic here).
-- A user's marketing membership is already derivable from Step 2 via
--   user_roles ur join roles r on r.id = ur.role_id and r.code = 'marketing'.
-- The Marketing same-date overlap EXEMPTION (marketing users may be booked on
-- overlapping projects; everyone else is subject to project-date + leave
-- conflicts) is enforced later in the project-team assignment RPC / business
-- rule (Sprint 9, project-team step) — NOT here. Marketing is a first-class
-- role and is never mapped to designer or any other role.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Reference catalog data (photographer types). Idempotent. Values are the
-- canonical types from the frozen schema (§3.1) and the Flutter model
-- (_kPhotoTypes). No invented types. NO users/accounts/projects/leave records.
-- ---------------------------------------------------------------------------
insert into public.photographer_types (code, name_ar) values
  ('photo',     'مصور فوتوغرافي'),
  ('video',     'مصور فيديو'),
  ('instagram', 'انستقرام'),
  ('design',    'تصميم')
on conflict (code) do update set name_ar = excluded.name_ar;

-- ---------------------------------------------------------------------------
-- Enable RLS (default-deny). NO policies yet → anon and authenticated have NO
-- access until Sprint 9 Step 6. Availability records are never public. Seeds
-- above run as table owner (bypasses RLS).
-- ---------------------------------------------------------------------------
alter table public.photographer_types      enable row level security;
alter table public.user_photographer_types enable row level security;
alter table public.user_unavailability      enable row level security;
