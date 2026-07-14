# supabase/ — local development scaffolding

**Sprint 9 · Step 1 — Development Foundation only.**

This directory prepares the repo for Supabase development. It is **scaffolding only**:

- ✅ standard structure: `config.toml`, `migrations/`, `functions/`, `seed.sql`
- ❌ **no** application tables, RLS, RPCs, or Edge Functions yet
- ❌ **no** remote link, no keys, no Flutter integration

## What's here
| Path | Purpose |
|---|---|
| `config.toml` | local stack config (no secrets, no project ref) |
| `migrations/` | empty (`.gitkeep`) — schema added in a later approved step |
| `functions/` | empty (`.gitkeep`) — Edge Functions added later |
| `seed.sql` | documentation-only; no data yet |
| `.gitignore` | ignores local artifacts + secrets (`.env`, `.branches`, `.temp`) |

## Docs
- `docs/SUPABASE_DEV_SETUP.md` — environment values, project environments, migration conventions
- `docs/BACKEND_SCOPE_GUARD.md` — the permanent "never create" list
- `docs/SUPABASE_CORE_PLAN.md` / `SCHEMA_DRAFT` / `RLS_PLAN` / `MIGRATION_PLAN` — the frozen design

## Guardrail
Never create tables, functions, migrations, or seeds for: **finance, payments, Rekaz, notifications, FCM, push notifications, reminders.** See `docs/BACKEND_SCOPE_GUARD.md`.
