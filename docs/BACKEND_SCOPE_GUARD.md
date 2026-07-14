# Backend Scope Guard

**Purpose:** a single, authoritative "never create" list for all backend work.
Applies to **schema, migrations, seed data, RPC functions, Edge Functions,
Flutter code, documentation, and all future backend work** — indefinitely,
unless the project owner explicitly reverses an exclusion in writing.

## 🚫 Never create

- **Finance** — no finance tables, columns, views, RPCs, Edge Functions, or logic.
- **Payments** — no payment tables or flows.
- **Payment requests** — no payment-request tables, RPCs, or endpoints.
- **Rekaz** — no Rekaz tables, config, integration, keys, or API handling.
- **Notifications** — no notification tables, RPCs, triggers, or delivery.
- **FCM / push notifications** — no device/token tables, no push infrastructure.
- **Reminders** — no reminder tables or functions.

## Explicit table/name denylist (non-exhaustive)

`finance_*`, `payments`, `payment_requests`, `transfers`, `invoices`,
`finance_reports`, `rekaz_*`, `notifications`, `notification_settings`,
`notification_*`, `reminders`, `reminder_*`, `devices`, `fcm_tokens`,
`push_*`.

## Related, allowed-but-bounded

- A team member's **`value`/fee** on a project assignment is **assignment
  metadata only** (decision context) — it must never become a payment,
  transfer, invoice, or finance report.
- `NotificationRepository` stays **interface-only, empty** in Flutter — no
  methods, no implementation, no provider, no backend counterpart.
- The `finance` / `wedding_finance` roles may exist as **inert role labels**
  for fidelity only — no finance tables, data, RPCs, or logic attach to them.

## How to enforce

- Before adding any table/function/migration, check the name against the
  denylist above.
- Code review + migration review must reject anything matching an excluded
  domain.
- If a feature seems to need one of these, **stop and ask the owner** — do not
  implement it under a different name.

_See also:_ `docs/SUPABASE_CORE_PLAN.md` §0 (hard guardrails) and `CLAUDE.md`
("Permanent Out of Scope").
