# Sumou Mobile App — Mobile UX Transformation

> How the **wide-screen web prototype** (sidebar + tables + grids + modals)
> becomes a **mobile-first, Arabic RTL, role-based** Flutter app. The HTML is a
> reference for **logic**, never for layout. When web layout and mobile
> usability conflict, **mobile usability wins**.

---

## Guiding principles

- **Mobile-first, not web-shrunk.** Design for a phone held one-handed during
  real fieldwork, not a resized desktop page.
- **RTL-native Arabic.** `Directionality(textDirection: TextDirection.rtl)` at
  the root; all text right-aligned; Arabic bottom-nav labels; Arabic date
  formatting via `intl`.
- **One primary CTA per screen.** Secondary actions go to an overflow menu or
  bottom sheet.
- **Large touch targets (≥ 44px), generous padding, rounded corners 12–18px.**
- **Show only permitted actions.** Hide actions the role/permission disallows.

---

## Web → Mobile pattern mapping

| Web prototype pattern | Mobile replacement |
|-----------------------|--------------------|
| Sidebar navigation | **Bottom navigation** (5 role-based tabs) + a **More** menu for overflow items |
| Data tables (projects, users) | **Cards** (`SumouProjectCard`, `SumouUserCard`) |
| Small confirmation modals | **Bottom sheets** (`SumouBottomSheet`) |
| Large/complex modal forms | **Full-screen pages**; long flows become **multi-step forms** (`SumouStepForm`) |
| Grid dashboards | **Stat cards** — 2-column when width allows, otherwise stacked |
| Desktop month-grid calendar | **Compact calendar + agenda list** below |
| Inline desktop toasts | **Snackbars / toasts** |
| Hover actions | **Tap** to open, **long-press / overflow** for quick actions |

---

## 1. Tables → Cards

Never render desktop tables for core flows. A **project card** shows:
- Project name
- Client name
- Project type (field / social / wedding)
- Date range
- Current status (status chip)
- Current stage
- Assigned photographers (avatars / chips)
- A quick-action button

**Card interaction:** tap → details; long-press or overflow → quick actions.

---

## 2. Modals → Bottom sheets or full screens

- **Small confirmations** (approve/reject closure, logout, delete): bottom sheet.
- **Long forms** (closure submission, stage update with notes): full-screen page.
- **Complex Add Project**: a **5-step form**:
  1. Project basic info
  2. Client / date info
  3. Assign manager
  4. Add photographers / roles
  5. Notes & review → **Save**

---

## 3. Grid dashboards → Mobile cards

Web grid dashboards become vertically scrolling **compact cards**. Use a
2-column stat-card layout when the screen is wide enough, otherwise stack.

**Manager home cards:** today summary · active projects count · pending closure
requests count · team availability summary · latest projects · quick actions
(Add project / View requests / View team).

**Photographer home cards:** my active projects · today/tomorrow schedule ·
pending requests · streak/summary placeholder · quick actions (Update stage /
Submit closure).

---

## 4. Calendar → Compact calendar + agenda

Avoid the desktop month grid with tiny event labels. Use a compact calendar
(e.g. `table_calendar`) with an **agenda list** of the selected day's items
below it. (Advanced calendar is a later sprint; Sprint 1–2 keep it minimal.)

---

## 5. Clear actions

- Exactly **one main CTA** per screen, styled with accent green `#A7CF5B`.
- Destructive/secondary actions live in an overflow menu or bottom sheet.
- Rejections / errors use red `#F0524B`.

---

## 6. RTL is native, not bolted-on

- Root `Directionality` is RTL; layouts use logical start/end, not left/right.
- Bottom-nav labels in Arabic; icons mirror correctly.
- Dates formatted in Arabic where possible.
- Forms, lists, chips, and headers all right-align.

---

## 7. Status chips (consistent vocabulary)

Use one `SumouStatusChip` component mapping these states to consistent colors:

| Chip | Meaning | Suggested color |
|------|---------|-----------------|
| نشط | Active | teal `#7FD4E0` / `#215C66` |
| منتهي | Ended | muted |
| بانتظار الموافقة | Awaiting approval | finance yellow `#F5C842` |
| مرفوض | Rejected | red `#F0524B` |
| مقبول | Accepted | green `#A7CF5B` |
| قيد التنفيذ | In progress | teal |
| جاري الإبداع | Creative in progress | project teal `#7FD4E0` |
| تم التسليم | Delivered | green `#A7CF5B` |

---

## Screen-by-screen transformation notes (Sprint 1 & 2)

| Screen | Web pattern | Mobile transformation |
|--------|-------------|-----------------------|
| Entry | Role-card grid / login box | Two large tappable cards: **دخول سمو**, **تتبع مشروع** |
| Login | Centered desktop form | Full-screen mobile form, large fields, single CTA |
| Role selection | Sidebar role list | Full-screen list of role cards (only if >1 role) |
| Dashboards | Sidebar + grid widgets | Bottom-nav shell + stacked/2-col stat cards |
| Projects list | Table with columns | Scrollable project cards + filter chips + search bar |
| Project details | Multi-column modal/page | Single-column: header → stage progress → team cards → notes → action bar |
| Add project | Big modal form | 5-step `SumouStepForm` |
| Assign photographers | Modal with table | Full-screen searchable photographer cards with select + capacity hint |
| Stages | Inline desktop stepper | `SumouProgressTimeline` (generic 3/7-stage) + update bottom sheet/page |
| Closure request | Modal upload | Full-screen: file picker + delivery-link field + submit |
| Approve/reject closure | Inline buttons | Bottom sheet with approve (green) / reject (red + reason) |
| Team | Photographer table | `SumouUserCard` grid/list with capacity indicator |
| Admin users/permissions | Table + edit modal | User cards → permission detail page (basic) |
| Client tracking | Inline result panel | `TrackProjectScreen` (code entry) → `ClientProjectResultScreen` (timeline, approved links only, «جاري الإبداع ⏳» when empty, rating later) |

---

## Design-system components (build before screens)

`SumouScaffold` · `SumouAppBar` · `SumouBottomNav` · `SumouCard` ·
`SumouButton` · `SumouTextField` · `SumouDropdown` · `SumouStatusChip` ·
`SumouStatCard` · `SumouProjectCard` · `SumouUserCard` · `SumouSectionHeader` ·
`SumouEmptyState` · `SumouBottomSheet` · `SumouStepForm` ·
`SumouProgressTimeline`.

**Visual rules:** dark bg `#152127`; cards `#1E2E35` / `#243840`; green
`#A7CF5B` for primary CTAs; teal `#215C66` for brand; red `#F0524B` for errors;
subtle borders; rounded 12–18px; generous padding; safe areas; ≥44px targets;
no dense text; no desktop tables.

---

## Universal UI states

Every async/list screen must wire:
- **Loading** state (skeleton/spinner).
- **Empty** state (`SumouEmptyState`) for no data.
- **Error** state for failed fetch/auth.
- **Pull-to-refresh** on lists.
- **Search + filter** on project/team lists.
- **Bottom sheet** confirmations and **snackbar/toast** feedback.
