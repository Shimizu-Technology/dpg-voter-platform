# Election-Day Operator Readiness Checklist

Last updated: 2026-04-20

Goal: confirm campaign staff, role assignments, and field workflows are ready before live election-day usage.

---

## 1) Staff and Role Roster

- Confirm one owner for each role:
  - `campaign_admin` (final authority)
  - `district_coordinator` (district operations)
  - `village_chief` (village-level operations)
  - `poll_watcher` (precinct reporting + strike list)
- Confirm no shared accounts between operators.
- Confirm every operator can log in with their own account.

Pass if each required role has an active, login-verified user.

---

## 2) Assignment Scope Validation

- Confirm the completed GEC import intended for election day is activated.
- For each `poll_watcher`, verify assigned village/precinct scope is correct.
- For live rehearsal, prefer explicit precinct assignments over village fallback and document any accounts still using fallback scope.
- For each `district_coordinator`, verify assigned district is correct.
- Spot-check at least two users by opening election-day pages and validating visible precincts/villages.
- Confirm out-of-scope access is denied (route + API).

Pass if the active GEC list and visible precinct data match intended assignments and unauthorized scope is blocked.

---

## 3) Operational Rehearsal (Dry Run)

- Run the simulation in:
  - `docs/testing/election-day-strike-list-simulation-checklist.md`
- Ensure at least one full cycle:
  - poll watcher updates full-voter turnout
  - war room logs linked supporter contact outcomes where applicable
  - war room matched supporter queue and unmatched-supporter bucket update
  - audit records generated

Pass if dry run completes without blocking defects.

---

## 4) Incident and Escalation Readiness

- Confirm escalation owner for:
  - login/auth failures
  - API outages
  - precinct data mismatches
- Confirm backup communication channel (phone/chat group) is active.
- Confirm expected response times for critical blockers.

Pass if escalation path is documented and acknowledged by operations leads.

---

## 5) Data and Compliance Checks

- Confirm compliance note is visible on strike-list workflow.
- Confirm turnout and contact updates are auditable.
- Confirm no role can bypass scope restrictions via direct URL/API.

Pass if compliance context and auditability are verified.

---

## 6) Day-Of Startup Checklist

- 60 min before polls:
  - Validate app uptime + login for key operators
  - Confirm poll watcher precinct lists load
  - Confirm war room dashboard/queue loads
- 30 min before polls:
  - Run one quick "test" update (if campaign policy allows) and rollback/annotate appropriately
  - Confirm activity feed and queue counters react

Pass if startup checks complete with no unresolved blockers.

---

## Sign-Off Template

- Environment used:
- Operator roster verified by:
- Assignment verification status: Pass / Fail
- Dry-run simulation status: Pass / Fail
- Escalation readiness status: Pass / Fail
- Overall readiness: GO / NO-GO
- Blocking issues:
- Owner + ETA for blockers:
