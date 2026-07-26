-- =============================================================================
-- Sprint 9 · Step 5 — Closure requests & client-facing project links
-- Domain: closure_requests, project_links (+ the closure_status enum).
-- Runs AFTER:
--   20260714120000_identity_and_access.sql          (public.profiles)
--   20260714130000_photographer_types_and_availability.sql
--   20260714140000_projects_core.sql                (public.projects)
--
-- Frozen decisions applied (see docs/SUPABASE_CORE_PLAN.md §1 / SCHEMA_DRAFT
-- §1, §4.5, §4.6):
--   Closure workflow data (retained history — approved/rejected rows are kept).
--   D4 delivery is URL-based links with approval + client-visibility gating;
--      Supabase Storage is DEFERRED (no buckets, no file-upload fields).
--   D6 soft delete on project_links (is_active / deleted_at / deleted_by).
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): creates NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders constructs. `report_file_url` is a plain
-- text URL field (Storage deferred), NOT a file-upload mechanism.
--
-- Scope (Step 5 ONLY): NO RPCs (submit/approve/reject/track), NO Edge Functions,
-- NO RLS policies, NO anon/public SELECT, NO security-definer tracking function,
-- NO automatic project-status changes, NO client_reviews table (deferred — see
-- note below), NO roles/permissions changes, NO Storage buckets. Those belong to
-- Step 6 (RLS + RPCs) and later. No Flutter or package changes.
--
-- RLS: enabled on every table below with NO policies yet → default-deny for anon
-- and authenticated until Sprint 9 Step 6.
--
-- Client reviews (SCHEMA_DRAFT §4.7): DEFERRED. There is no standalone Flutter
-- ClientReview contract (rating/message live on ClientTrackingModel and are
-- submitted via the future anon submit_review RPC), and this step is scoped to
-- closure requests + project links only. The table is intentionally NOT created
-- here and remains deferred to the tracking/RPC step. Nothing invented.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- closure_status enum (SCHEMA_DRAFT §1). Values mirror the Flutter
-- ClosureRequestStatus keys exactly (pending/approved/rejected). Not created in
-- Step 4 (deferred to this step). No other status values are invented.
-- ---------------------------------------------------------------------------
create type public.closure_status as enum ('pending', 'approved', 'rejected');

-- ---------------------------------------------------------------------------
-- closure_requests (SCHEMA_DRAFT §4.5) — a photographer's request to close/
-- deliver a project, reviewed by the manager. RETAINED HISTORY: approved and
-- rejected rows are kept (no soft-delete columns, no hard-delete workflow).
-- Fields match the frozen schema and ClosureRequestModel exactly. No reviewed_by
-- and no updated_at — neither is in the frozen schema or the Flutter contract,
-- so neither is added (and no updated_at trigger).
-- ---------------------------------------------------------------------------
create table public.closure_requests (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects (id) on delete cascade,
  -- Submitter (photographer). restrict: keep referential integrity for retained
  -- history — profiles are soft-deleted (D6), never hard-removed.
  submitted_by    uuid not null references public.profiles (id) on delete restrict,
  status          public.closure_status not null default 'pending',
  -- Delivery/report are plain text URLs (Storage deferred, D4). NOT file uploads.
  delivery_link   text,
  report_file_url text,
  notes           text,
  -- Set when a manager rejects. Plain nullable text (no cross-field CHECK — the
  -- frozen schema defines none; reason presence is enforced by the future RPC).
  reject_reason   text,
  reviewed_at     timestamptz,
  created_at      timestamptz not null default now()
);
comment on table public.closure_requests is
  'Photographer closure/delivery requests, manager-reviewed. Retained history (approved/rejected kept; no soft/hard delete). Status flips and project-status changes are done by the future RPCs, not here.';
comment on column public.closure_requests.report_file_url is
  'Plain text URL only (Supabase Storage deferred, D4). NOT a file-upload field.';

-- One OPEN (pending) closure request per project. Approved/rejected rows are
-- unconstrained, so a project may accumulate history and re-request after a
-- rejection. This partial unique index is exactly how a duplicate pending
-- request is prevented (a second insert with status='pending' for the same
-- project violates it).
create unique index closure_requests_one_pending_per_project_uidx
  on public.closure_requests (project_id)
  where status = 'pending';

-- Reads: by project (detail/history) and by status (queues). Not excessive.
create index closure_requests_project_idx on public.closure_requests (project_id);
create index closure_requests_status_idx  on public.closure_requests (status);

-- ---------------------------------------------------------------------------
-- project_links (SCHEMA_DRAFT §4.6, D4/D6) — URL-only client-facing delivery
-- links. NO Storage, NO file uploads. Soft delete (D6). A link is eligible for
-- future public client tracking ONLY when
--   is_approved AND is_client_visible AND is_active AND deleted_at IS NULL.
-- That gating is data here; it is ENFORCED later by the security-definer
-- track_by_serial RPC (Step 6) — there is deliberately no anon/public policy in
-- this migration, so these rows are not reachable by clients yet.
-- `created_by` is included per the Step 5 instruction (extends the §4.6 draft,
-- symmetric with deleted_by); no updated_at (not in the frozen schema).
-- ---------------------------------------------------------------------------
create table public.project_links (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references public.projects (id) on delete cascade,
  label             text not null,
  url               text not null,
  is_approved       boolean not null default false,
  is_client_visible boolean not null default false,
  is_active         boolean not null default true,
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  deleted_by        uuid references public.profiles (id) on delete set null,
  constraint project_links_label_not_blank_chk check (char_length(btrim(label)) > 0),
  -- Safe "URL only" validation (frozen §4.6): non-blank and an http(s) URL.
  -- Rejects empty strings and non-http schemes (e.g. javascript:). No Storage.
  constraint project_links_url_http_chk check (url ~* '^https?://\S')
);
comment on table public.project_links is
  'URL-only client-facing delivery links (D4). No Storage/file uploads. Soft delete (D6). Publicly eligible only when is_approved AND is_client_visible AND is_active AND deleted_at IS NULL — enforced by the future track_by_serial RPC, not by any policy in this step.';

-- Reads: all links for a project (staff management).
create index project_links_project_idx on public.project_links (project_id);
-- Supports the future public-eligibility lookup. The partial predicate is the
-- COMPLETE client-tracking eligibility rule, so a soft-deleted or inactive link
-- is excluded from this index and can never qualify for tracking:
--   is_approved AND is_client_visible AND is_active AND deleted_at IS NULL.
create index project_links_public_idx
  on public.project_links (project_id)
  where is_approved and is_client_visible and is_active and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Enable RLS (default-deny). NO policies yet → anon and authenticated have NO
-- access until Sprint 9 Step 6. No public/anon SELECT, no tracking RPC. Client
-- tracking stays anonymous and serial-driven via a restricted security-definer
-- RPC added later (NOT here); no client_tracking role is added to the catalog.
-- No seed/reference data is inserted in this step.
-- ---------------------------------------------------------------------------
alter table public.closure_requests enable row level security;
alter table public.project_links    enable row level security;
