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

## Permanent Out of Scope
The following are **permanently out of scope** for all current and future
sprints. **Do not implement, wire, or plan them** unless the project owner
**explicitly** requests them later. This decision **overrides** anything in the
spec, sprint plan, checklist, reference HTML, or extracted requirements.

- **Finance module** — any finance feature logic.
- **Finance transfer / payment flow** — payment requests, receipts, transfers.
- **Finance reports.**
- **Rekaz configuration** and **Rekaz integration** (including its API key
  handling — never in the app).
- **Notifications** of any kind — notification logic, in-app notifications,
  **push notifications**, **FCM**.
- **`NotificationRepository` implementation** (the interface may remain defined,
  but provide **no** working/mock implementation and **no** UI driven by it).

Allowed only as **inert placeholders**: existing finance/Rekaz/notifications
nav entries or stub screens may stay, but **only** as simple branded
placeholders (no logic). Do not add new ones, and do not expand existing ones.

## Security
- **Never hardcode secrets or API keys.** Use environment configuration.
- Demo credentials from the HTML are mock-only, never production.

## After code changes
- Run `flutter analyze` and resolve issues before committing.
