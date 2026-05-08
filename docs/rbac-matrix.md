# Campaign Tracker RBAC Matrix

Last updated: 2026-03-02

This document defines which roles can access which parts of the app.  
It is the operational reference for QA, onboarding, and future permission changes.

---

## Roles

- `campaign_admin`
- `district_coordinator`
- `data_team`
- `village_chief`
- `block_leader`
- `poll_watcher`

---

## Permission Rules (Current)

| Capability | campaign_admin | data_team | district_coordinator | village_chief | block_leader | poll_watcher |
|---|---|---|---|---|---|---|
| Dashboard (`/admin`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| View supporters (`/admin/supporters`, `/admin/supporters/:id`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Create staff entry (`/admin/supporters/new`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit supporter fields | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Village detail (`/admin/villages/:id`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Events + check-in (`/admin/events*`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| QR tools (`/admin/qr`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Leaderboard (`/admin/leaderboard`) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| War room (`/admin/war-room`) | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Poll watcher (`/admin/poll-watcher`) | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| SMS center (`/admin/sms`) | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| User management (`/admin/users`) | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |

---

## User Management Scope

User management is available to:

- `campaign_admin` (full role management)
- `district_coordinator` (limited role management)

Coordinator limitations:

- Can manage only: `village_chief`, `block_leader`, `poll_watcher`
- Cannot assign or modify: `campaign_admin`, `district_coordinator`

Data-team notes:

- `data_team` has coordinator-level operational access for supporter data, reports, and GEC workflows.
- `data_team` **cannot** manage users/roles.

---

## Enforcement Strategy

RBAC is enforced in two layers:

1. **Backend (authoritative)**
   - Controller guards in `api/app/controllers/concerns/authenticatable.rb`
   - Role-specific checks applied per API controller
2. **Frontend (UX)**
   - Session permissions from `GET /api/v1/session`
   - Dashboard/nav only shows allowed tools
   - Route-level permission guards prevent direct URL access

Both layers must stay aligned.

---

## Source of Truth in Code

- Permission helpers:
  - `api/app/controllers/concerns/authenticatable.rb`
- Session permission payload:
  - `api/app/controllers/api/v1/session_controller.rb`
- Frontend session hook:
  - `web/src/hooks/useSession.ts`
- Frontend route guards:
  - `web/src/App.tsx`
- Dashboard conditional navigation:
  - `web/src/pages/admin/DashboardPage.tsx`

---

## QA Checklist (RBAC Smoke Test)

For each role, verify:

1. Sign in and open `/admin`
2. Only permitted tools are visible in nav/actions
3. Attempt direct URL access to disallowed routes:
   - Expect "Not Authorized" (frontend) and `403` (backend API)
4. For supporter detail:
   - Edit button shown only for admin/coordinator
5. For users page:
   - Coordinator sees only allowed roles for invite/edit

---

## Change Policy

When changing role permissions:

1. Update this file first
2. Update backend guards
3. Update `/api/v1/session` payload
4. Update frontend nav/route guards
5. Add/adjust controller tests
6. Re-run RBAC smoke tests
