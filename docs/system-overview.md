# Campaign Tracker System Overview

Last updated: 2026-02-13

This is the practical "how the app works" guide for engineering, QA, and operations.

---

## 1) What This App Does

Campaign Tracker supports three core workflows:

1. Public supporter signup (no staff login required)
2. Staff operations (supporters, villages, events, check-in, outreach)
3. Election-day monitoring (poll watcher reports and war room visibility)

---

## 2) High-Level Architecture

Monorepo structure:

- `api/` - Rails 8 JSON API
- `web/` - React + TypeScript + Vite frontend
- `docs/` - build, execution, QA, and RBAC references

Runtime model:

- Frontend calls API at `/api/v1/*`
- Authenticated users sign in through Clerk in the web app
- API validates Clerk JWT and maps to local `User` records
- Real-time updates are broadcast through ActionCable plus polling fallback
- Background jobs handle slow external work (SMS, invite email)

---

## 3) Auth and User Provisioning

### Staff auth flow

1. User signs in/signs up in Clerk UI from `/admin`
2. Web obtains Clerk token and sends `Authorization: Bearer ...` to API
3. API decodes JWT and finds local `User` by `clerk_id`
4. If not found, API links by email (including Clerk API fallback lookup when needed)
5. Local `User` role determines allowed pages/actions

### Invite flow

1. Authorized user creates/invites a staff user from `/admin/users`
2. API pre-creates local `User` record with email + role
3. Background job sends invite email via Resend
4. Invitee creates Clerk account with invited email
5. On first login, Clerk user links to local `User` by email

Related files:

- `api/app/controllers/concerns/authenticatable.rb`
- `api/app/controllers/api/v1/users_controller.rb`
- `api/app/services/user_invite_email_service.rb`
- `api/app/jobs/send_user_invite_email_job.rb`

---

## 4) Role and Permission Model

RBAC is enforced in both backend and frontend.

- Backend guards live in `Authenticatable`
- Frontend session permissions come from `GET /api/v1/session`
- Route guarding happens in `web/src/App.tsx`
- Dashboard nav visibility is role-aware in `web/src/pages/admin/DashboardPage.tsx`

See full matrix: `docs/rbac-matrix.md`

---

## 5) Core Functional Flows

### A) Public signup

- Route: `/signup` (or `/signup/:leaderCode`)
- Creates supporter through `POST /api/v1/supporters`
- Stores source attribution (`qr_signup` or `staff_entry`)
- Queues welcome SMS asynchronously

### B) Staff supporter operations

- Supporter list/detail pages under `/admin/supporters*`
- Role-gated edits (admin + coordinator)
- Audit trail is recorded for create/update actions

### C) Village and precinct operations

- Village detail page `/admin/villages/:id`
- Unassigned precinct supporters can be assigned by authorized roles

### D) Event lifecycle

- Create/manage events under `/admin/events*`
- Check-in flow at `/admin/events/:id/checkin`
- Attendance metrics and history available per event

### E) Election day workflows

- Poll watcher submissions under `/admin/poll-watcher`
- War room command view at `/admin/war-room`
- Live reporting + activity feed

---

## 6) Data Domain (Key Entities)

Primary models:

- `User` - role, identity, assignment scope
- `Supporter` - core voter/supporter record
- `Village`, `Precinct`, `Block` - geographic hierarchy
- `Event`, `EventRsvp` - event invitation and attendance
- `PollReport` - election-day turnout report snapshots
- `AuditLog` - accountability trail for data changes

---

## 7) Real-Time and Background Processing

Real-time:

- ActionCable used for campaign updates to dashboard/war-room style views
- Client also uses periodic query refetch as fallback

Background jobs:

- `SendSmsJob` - outbound SMS
- `SmsBlastJob` - batch outreach
- `EventNotifyJob` - event notifications
- `SendUserInviteEmailJob` - staff invite emails

---

## 8) API and Frontend Integration Pattern

Frontend:

- API client in `web/src/lib/api.ts`
- Data fetching with React Query
- Session permissions hook: `web/src/hooks/useSession.ts`

Backend:

- Versioned JSON endpoints in `api/app/controllers/api/v1`
- Shared auth/permission helpers in `Authenticatable`
- Standard API error envelope used for permission and validation failures

---

## 9) Operational Notes

- Permission changes must update both backend guards and frontend visibility rules
- Always validate with role-based tests and route-access smoke checks
- Keep docs aligned:
  - `docs/rbac-matrix.md` for role boundaries
  - `docs/execution-tracker.md` for current implementation status
  - `docs/build-plan.md` for phased delivery intent

---

## 10) Recommended Onboarding Reading Order

1. `README.md`
2. `docs/system-overview.md` (this file)
3. `docs/rbac-matrix.md`
4. `docs/execution-tracker.md`
5. `docs/build-plan.md`
