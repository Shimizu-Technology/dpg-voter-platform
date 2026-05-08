# Stabilization Sprint Checklist

Last updated: 2026-02-15

Goal: remove intermittent reliability issues before new feature expansion.

---

## Sprint Scope

- Auth/session stability in admin flows
- ActionCable disconnect/reconnect reliability
- Release smoke checks for production confidence
- Evidence logging and pass/fail gates

---

## Owners

- Engineering owner:
- QA owner:
- Operations owner:
- Start date:
- Target end date:

---

## A) Auth and Session Stability

### A1. Reproduce and baseline
- Run admin for 10-15 minutes with normal usage.
- Include idle time and tab switching.
- Capture baseline:
  - count of `401` responses for:
    - `/api/v1/session`
    - `/api/v1/dashboard`
  - number of visible "Can't connect to server" events.

Pass criteria:
- Baseline evidence captured with timestamps and environment details.

### A2. Long-session behavior check
- Sign in and keep `/admin` open for >= 20 minutes.
- Switch tabs every 2-3 minutes.
- Return to app and navigate between:
  - `/admin`
  - `/admin/supporters`
  - `/admin/war-room`
  - `/admin/poll-watcher`

Pass criteria:
- No recurring 401 loop.
- No forced page reload needed to recover.

### A3. Focus/visibility recovery check
- Background tab for 1-3 minutes.
- Return and trigger 2-3 API actions.

Pass criteria:
- Session stays valid and requests succeed without auth errors.

---

## B) ActionCable Reliability

### B1. Connection health
- Keep app open on pages using realtime updates:
  - `/admin/war-room`
  - `/admin/poll-watcher`
- Observe connection behavior for >= 15 minutes.

Pass criteria:
- No persistent disconnected state.
- Reconnect succeeds when network recovers.

### B2. Fallback freshness
- During cable disruption simulation (network throttle/offline toggle), verify polling fallback still updates key data.

Pass criteria:
- Core election-day pages remain operational and reasonably fresh.

---

## C) Release Smoke Gate (every deploy)

Run after each deployment:

1. Login works from clean browser session.
2. `/admin` loads successfully.
3. `/api/v1/session` returns authenticated response.
4. Open `/admin/supporters`, `/admin/events`, `/admin/war-room`, `/admin/poll-watcher`.
5. Idle 5 minutes, switch tabs, return, verify no disconnect error.
6. Trigger one write action (example: poll report or supporter update) and verify success.

Pass criteria:
- All checks pass with no blocker defects.

---

## D) Logging and Metrics Capture

Capture for each test run:
- Environment (local/staging/prod)
- Build/commit SHA
- Browser/device used
- Time window
- Observed 401 counts by endpoint
- Observed ActionCable reconnect events
- Any user-facing errors

---

## E) Exit Criteria for Stabilization Sprint

Mark sprint complete only when all are true:
- No reproducible intermittent auth/session disconnect in defined test window.
- No critical ActionCable reliability blockers.
- Release smoke gate passes on two consecutive deployments.
- Defects are documented with owner + ETA, or resolved.

---

## F) Defect Log Template

- ID:
- Area: (auth/session | actioncable | api | frontend)
- Environment:
- Steps to reproduce:
- Expected:
- Actual:
- Severity:
- Owner:
- ETA:
- Status:
