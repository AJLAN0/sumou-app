# Supabase Dev Setup — Sprint 9 · Step 1 (Development Foundation)

**Scope of this step:** prepare the repo for Supabase development **safely**, without creating the application schema.

**Done in Step 1:** local `supabase/` scaffolding (config + empty dirs + doc-only seed), `.gitignore` for secrets, `.env.example`, and this documentation.
**NOT done (by design):** database tables, RLS, RPCs, Edge Functions, Flutter↔Supabase wiring, Supabase Flutter packages, remote linking, Sprint 9 Step 2.

> **Supabase CLI availability:** the CLI was **not available** in the automation environment, so the `supabase/` structure was created **manually** (equivalent to `supabase init`, minus running the tool). You can regenerate/validate it locally with the CLI (see below) — the layout matches the standard output.

---

## 1. Environment values (required later)

| Variable | Used by | Notes |
|---|---|---|
| `SUPABASE_URL` | Flutter app (later), CLI | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | Flutter app (later) | public, RLS-gated key |
| `SUPABASE_PROJECT_REF` | CLI only | for `supabase link` (later, with approval) |
| `SUPABASE_SERVICE_ROLE_KEY` | **server only** | ⛔ never in Flutter, never committed |

**Rules (enforced):**
- **Never commit real keys.** Only `.env.example` (placeholders) is tracked; real `.env*` is gitignored.
- **Never put `service_role` in Flutter** — it bypasses RLS. It belongs only in trusted server contexts (e.g. a future Edge Function's secrets, set via the dashboard/CLI, not a file).
- **Never store secrets in source-controlled files.** Local `.env`, `supabase/.env`, `.branches/`, `.temp/` are all ignored.
- The **internal auth email** (`normalized_username@users.sumou.internal`, decision D2) is an implementation detail — never displayed, never a "secret", but also never a real inbox.

### How env reaches the app (later)
When Flutter integration begins (a later step), values are injected at build time via `--dart-define` (or `--dart-define-from-file`), read with `String.fromEnvironment(...)`. No secrets are baked into source. **Not implemented in Step 1.**

---

## 2. Project environments — DEV + PROD (owner-approved)

Two separate Supabase **cloud** projects, plus an optional local stack for fast
iteration. **The same tracked migrations** flow through all of them — the schema
is defined once, in `supabase/migrations/`, and promoted forward-only.

| Environment | Supabase project | Purpose | Notes |
|---|---|---|---|
| **Local** (optional) | none (containers) | fast, disposable inner loop | needs Docker **or** Colima/OrbStack; skip if Docker is unavailable |
| **Development** | `sumou-dev` | integration / testing | apply here first, verify |
| **Production** | `sumou-prod` | live | apply the **identical** migrations after DEV is verified |

Each project has its **own** ref, URL, anon key, DB password, and service_role.

**Rules:**
- **Same migrations everywhere** — never hand-edit a remote DB; the migration
  files are the single source of truth (see §3).
- **Promotion is forward-only:** local/DEV → verify → PROD. Never push an
  unverified migration straight to PROD.
- **PROD is deliberate:** link/push to `sumou-prod` only as an intentional,
  reviewed action (ideally via CI — see §5b). Never point local dev tooling at
  PROD by accident.
- **Secrets are per-project and never committed:** service_role is server-only
  (never in Flutter); URL + anon key per environment live in local `.env*`
  (gitignored) or CI secrets.

---

## 3. Migration conventions (for the future apply-step)

- **Timestamped names:** `supabase/migrations/<UTC timestamp>_<domain>.sql` (e.g. `20260715120000_roles_and_profiles.sql`). The CLI generates the timestamp via `supabase migration new <name>`.
- **One logical domain per migration** (e.g. roles/permissions, projects, team, closures) — not one giant file.
- **Forward-only:** no destructive rewrites of applied migrations; fix-forward with a new migration.
- **No manual production edits:** every schema change goes through a tracked migration. Never edit a remote DB by hand.
- **All schema changes tracked in migrations** — nothing lives only in a dashboard.
- **Reproducible from empty:** `supabase db reset` (local) must rebuild the entire schema from migrations + `seed.sql` with no manual steps.
- **Order matches the plan:** enums/lookups → identity/roles/permissions → projects → team/stages → closures/links/reviews → RLS → RPCs → Edge Functions (see `docs/SUPABASE_MIGRATION_PLAN.md`).

---

## 4. Backend scope guard

See **`docs/BACKEND_SCOPE_GUARD.md`** — the authoritative "never create" list:
finance, payments, payment requests, Rekaz, notifications, FCM/push, reminders.
This applies to schema, migrations, seed, RPCs, Edge Functions, Flutter, and docs — now and in every future step.

---

## 5. Local commands you (the owner) run manually

> These are **for you to run locally** — nothing here is run by the automation, and nothing touches a remote project.

```bash
# 1) Install the Supabase CLI (if not installed)
#    macOS:  brew install supabase/tap/supabase
#    others: https://supabase.com/docs/guides/cli/getting-started

# 2) (Optional) validate/regenerate the local structure — it already exists,
#    so `supabase init` will refuse to overwrite, which is expected.
supabase init          # no-op if supabase/ already present

# 3) Start the local stack (Docker required). Verifies config.toml is valid.
supabase start         # prints local API URL + anon key for LOCAL use

# 4) Stop it when done
supabase stop

# 5) Copy the env template and fill LOCAL values from `supabase start` output
cp .env.example .env   # .env is gitignored — never commit it
```

**Local** commands above need Docker (or a Docker-compatible runtime: Colima /
OrbStack). If you can't run Docker, use the remote DEV path below.

### 5a. Remote DEV apply — Docker-free (owner-approved, **DEV only**)

`supabase db push` connects **directly to the remote Postgres over the network**,
so it needs **no local container runtime**. A real Supabase project provides the
`auth` schema, so the `profiles → auth.users` FK works (a bare local Postgres
would not).

```bash
# 0) One-time: create a DEV project at https://supabase.com/dashboard
#    Copy its Project Ref (Settings → General) and DB password (Settings → Database).

supabase login                                   # browser access-token flow
supabase link --project-ref <YOUR_DEV_PROJECT_REF>   # prompts for the DB password
supabase migration list                          # preview local vs remote
supabase db push                                 # apply Step 2 + Step 3 to DEV
```

**Rules (still enforced):**
- 🟢 **DEV only — never `link` or `push` to Production.**
- 🔒 `supabase link` writes to `supabase/.temp/` (gitignored). Never commit the DB
  password, access token, or any key. The app's URL + anon key go in a local
  `.env` (gitignored).
- Do not use the Supabase MCP `apply_migration` for this — always go through the
  tracked migration files + `db push` so the schema stays reproducible.

### 5b. Promotion: DEV → PROD (same migrations, forward-only)

The CLI links to **one** project at a time (stored in `supabase/.temp/`), so you
switch by re-linking. Apply to DEV first, verify, then apply the **identical**
migrations to PROD.

```bash
# --- DEV ---
supabase link --project-ref <SUMOU_DEV_REF>
supabase db push
# ...verify in the DEV dashboard (tables + seeds)...

# --- PROD (deliberate) ---
supabase link --project-ref <SUMOU_PROD_REF>
supabase migration list      # confirm exactly the intended migrations are pending
supabase db push             # applies the SAME files to PROD
```

**Recommended (long term): automate with CI** so PROD is never a manual laptop
push. A GitHub Actions job using `supabase/setup-cli` can run `db push` against
DEV on a dev branch and against PROD on `main`, with each project's ref + DB
password stored as **CI secrets** (never in the repo). Ask and I can scaffold the
workflow file (with placeholder secret names — no real values).

### 5c. Flutter env separation (later, when the app connects)

Per-environment `SUPABASE_URL` + anon key via `--dart-define-from-file`:
`flutter run --dart-define-from-file=env/dev.json` (and `env/prod.json` for
release builds). Keep `env/*.json` gitignored; commit only `*.example` templates.
**service_role never appears in any Flutter build.**

---

## 6. What Step 1 explicitly did NOT do

- ❌ create database tables / schema
- ❌ write migration SQL implementing the schema
- ❌ add RLS policies or RPCs
- ❌ connect Flutter to Supabase / add Supabase Flutter packages
- ❌ modify repository implementations or any Flutter file
- ❌ link or configure a remote (DEV or PROD) project
- ❌ start Sprint 9 Step 2

Step 2 begins only when explicitly requested.
