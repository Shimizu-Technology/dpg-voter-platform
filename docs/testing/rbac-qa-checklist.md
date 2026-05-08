# RBAC QA Checklist

Last updated: 2026-02-13

Goal: validate that each role only sees and accesses what it should.

Reference matrix: `../rbac-matrix.md`

---

## Test Accounts Needed

Create or confirm one account per role:

- `campaign_admin`
- `district_coordinator`
- `village_chief`
- `block_leader`
- `poll_watcher`

If possible, use separate browser profiles (or incognito windows) for parallel testing.

---

## Global Checks (Run For Every Role)

1. Sign in and open `/admin`
2. Confirm only expected tool buttons are visible in dashboard nav
3. Try direct navigation to restricted routes (paste URL in address bar)
4. Confirm restricted route shows "Not Authorized" state (frontend)
5. Confirm API calls for restricted actions return `403` (backend)

---

## Route Access Matrix (Expected)

| Route | admin | coordinator | chief | leader | poll_watcher |
|---|---|---|---|---|---|
| `/admin` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `/admin/supporters` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/supporters/new` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/supporters/:id` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/villages/:id` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/events` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/events/:id` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/events/:id/checkin` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/qr` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/leaderboard` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `/admin/war-room` | ✅ | ✅ | ✅ | ❌ | ✅ |
| `/admin/poll-watcher` | ✅ | ✅ | ✅ | ❌ | ✅ |
| `/admin/sms` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `/admin/users` | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## Action-Level Permission Checks

### Supporters

- Admin/coordinator can edit supporter and save
- Chief/leader can open supporter detail but cannot edit
- Poll watcher cannot access supporter pages

### Users

- Admin can create/edit all roles
- Coordinator can only create/edit:
  - `village_chief`
  - `block_leader`
  - `poll_watcher`
- Coordinator cannot create/edit:
  - `campaign_admin`
  - `district_coordinator`

### SMS

- Admin/coordinator can open SMS page and submit actions
- Other roles do not see SMS in nav and cannot open route

### Election-Day Tools

- Poll watcher can access:
  - `/admin/poll-watcher`
  - `/admin/war-room`
- Poll watcher cannot access supporter/events/users/sms pages

---

## API Spot Checks (Optional but Recommended)

Use DevTools network or API client while signed in as each role:

- `GET /api/v1/session` returns expected permission flags
- Restricted endpoints return `403` with appropriate error codes
- Allowed endpoints return `200`/`201` as expected

---

## Defect Logging Template

- Role:
- Route:
- Action:
- Expected:
- Actual:
- Repro steps:
- Screenshot/log link:
