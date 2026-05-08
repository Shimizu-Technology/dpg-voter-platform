# App Status and Stabilization Plan (2026-02-15)

This document captures:
- what the campaign team asked for in the first demo meeting,
- what is already implemented in the app,
- current stability issues observed during live/local testing,
- and the prioritized next steps.

---

## 1) Meeting Summary (Campaign Team Demo)

Primary themes from the meeting:

- Reliability and trust are top priority (no random disconnects/timeouts in live usage).
- Data entry should match campaign operations:
  - first name + last name (instead of only full name),
  - vetting/review stage before records count as final,
  - duplicate flagging for review (do not hard-block data entry).
- Outreach operations need clear segmentation:
  - registered vs not registered voters,
  - yard sign / motorcade interest,
  - opt-in communication preferences (text/email/both),
  - blast workflows that scale to large audiences.
- Election-day workflows must be practical and auditable:
  - poll watcher updates,
  - war room queue visibility,
  - clear reporting of progress by village/district.
- Operational refinements:
  - configurable quotas and voter numbers,
  - import from existing sheets,
  - export to Excel with filter-respecting output,
  - better QR signup usability (village dropdown),
  - CTA/social links and branding/domain readiness.

Open strategic questions from meeting:
- WhatsApp vs SMS operating model.
- Absentee ballot tracking approach (MVP scope TBD).
- Exact owner/workflow for final vetting sign-off.

---

## 2) Current Implementation Status (High-Level)

Recent merged work has already delivered substantial portions of requested scope:

- Role + area scoping (staff visibility constrained by assignment).
- Name split and supporter data model upgrades.
- Vetting/verification workflow and duplicate review workflow.
- Import/export foundation (including Excel export).
- Quota/precinct configurability paths.
- Poll watcher + war room election-day operations flow.
- Performance hardening and operational docs/checklists.

Related execution source of truth:
- `docs/execution-tracker.md`

---

## 3) Observed Stability Incident

Symptom seen in local/prod-style usage:
- Admin dashboard intermittently switches to "Can't connect to server"
- then self-recovers without user action.

Evidence pattern from logs:
- one successful authenticated `/api/v1/dashboard` request (`200`)
- followed by repeated `/api/v1/session` + `/api/v1/dashboard` requests returning `401`
- then app eventually recovers.

Interpretation:
- This is most consistent with transient auth token synchronization gaps (Clerk token attach/refresh windows), not a database/query failure.

---

## 4) Stabilization Actions Applied

Auth token sync hardening has been applied in:
- `web/src/components/AdminLayout.tsx`

Changes:
- Added safer token sync behavior so transient token-null/fetch failures do not immediately clear existing auth headers.
- Added frequent keep-warm sync interval for token freshness.
- Added focus/visibility-triggered token sync on tab return.
- Added per-request token attach interceptor to ensure outbound API calls include a fresh token whenever possible.

Expected impact:
- Reduce intermittent 401 bursts caused by token attach timing issues.
- Prevent random dashboard/session disconnect loops during idle/tab-switch usage.

---

## 5) Priority Plan (Agreed Next Sequence)

### P0 - Stabilization Sprint (now)
- Monitor and eliminate intermittent auth/session failures.
- Add explicit observability checks for:
  - auth failure rate (`401`) by endpoint,
  - ActionCable disconnect/reconnect frequency.
- Create and run a short deploy smoke test after every release:
  - login,
  - dashboard,
  - session fetch,
  - war room/poll watcher open,
  - idle + tab-switch behavior.

### P1 - Operations Sign-Off Sprint
- Run delegated simulation and readiness checklists with campaign operators.
- Capture pass/fail + blockers + owners.
- Record go/no-go decision.

### P2 - Comms Model Decision
- Finalize channel matrix:
  - SMS, email, both, and/or WhatsApp path.
- Confirm consent/legal wording and delivery behavior.

### P3 - Absentee MVP
- Define minimal absentee support process and data markers.
- Implement only validated MVP path.

### P4 - Brand/Domain Polish
- Apply official branding assets and domain rollout.
- Verify production URL/QR consistency end-to-end.

---

## 6) Risks to Watch

- Token lifecycle edge cases under long-lived sessions.
- Websocket reliability under network jitter and browser sleep/wake.
- Scope leakage regressions when adding new endpoints/pages.
- Drift between operational process (team workflow) and system workflow.

---

## 7) Operational Tracking Notes

Use this file for stabilization status snapshots.

Suggested update cadence:
- daily during active stabilization,
- then per-release once stable.
