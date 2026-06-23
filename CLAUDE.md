# CLAUDE.md — Sumou Mobile App

Project rules for working in this repository. Keep them in mind on every change.

## What this is
A **Flutter, mobile-first** app for Sumou Creative. **Arabic RTL is the primary
interface** (English may be prepared, but Arabic comes first).

## Source of truth
- `docs/MASTER_SPEC.md` is the **source of truth**.
- The reference HTML in `docs/reference/` is for **logic only** — workflows,
  roles, permissions, statuses, Arabic labels, and brand colors.
- **Do not copy the HTML layout.** It is a wide-screen web prototype; rebuild
  every screen with mobile UX patterns. When web layout and mobile usability
  conflict, choose mobile usability.

## How to build
- Work **sprint by sprint** (see `docs/SPRINT_PLAN.md`); keep later modules as
  placeholders until their sprint.
- Use a **repository/service layer** — UI never calls the backend directly.
- Build and reuse **design-system components** (`Sumou*`); don't reinvent
  widgets per screen.

## Security
- **Never hardcode secrets or API keys.** Use environment configuration.
- Demo credentials from the HTML are mock-only, never production.

## After code changes
- Run `flutter analyze` and resolve issues before committing.
