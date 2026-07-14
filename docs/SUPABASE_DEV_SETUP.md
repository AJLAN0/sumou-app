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

## 2. Project environments

| Environment | Purpose | Status now |
|---|---|---|
| **Local** | `supabase start` on a developer machine; fast, disposable | scaffolded (this step) |
| **Development (remote)** | shared Supabase DEV project for integration | **not created / not linked** |
| **Production (remote)** | live project | **not configured, not linked** |

**Rules:**
- Do **not** configure Production yet.
- Do **not** link to Production.
- Do **not** apply anything remotely (local or dev) **without explicit owner approval**.
- Promotion path (later): local → DEV (apply migrations) → PROD (apply the *same* migrations), forward-only.

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

**Do not** run `supabase link`, `supabase db push`, or any remote/prod command in this step. Remote actions require explicit approval.

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
