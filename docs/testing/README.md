# Testing Handoff Pack

Last updated: 2026-02-13

This folder is the handoff package for manual QA by another engineer.

Use these documents in order:

1. `stabilization-sprint-checklist.md` - reliability-first gate before expanding scope
2. `rbac-qa-checklist.md` - verify role-based access control end-to-end
3. `critical-flow-regression-checklist.md` - verify core app workflows still work

Related references:

- `../rbac-matrix.md` - canonical role-permission definitions
- `../system-overview.md` - how the app works end-to-end
- `../execution-tracker.md` - what is done vs next

## Suggested QA Workflow

1. Run RBAC checklist first (highest risk for silent regressions)
2. Run core flow regression second
3. Run stabilization checklist whenever auth/session/cable behavior changes
4. Record failures with:
   - role/account used
   - exact route and action
   - expected vs actual
   - screenshot + terminal logs

## Pass Criteria

- No unauthorized page/action is visible to a role that should not have it
- No authorized action fails due to permission mismatch
- Critical public/admin flows complete without blockers
