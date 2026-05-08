# Critical Flow Regression Checklist

Last updated: 2026-02-13

Goal: confirm key workflows still work after permission and UX changes.

---

## 1) Public Signup Flow

- Open `/signup` in incognito (not logged in)
- Submit a valid supporter record
- Confirm success page appears
- Confirm supporter appears in admin supporters list
- Confirm source attribution is correct (`qr_signup` for public flow)

Pass if all steps succeed with no blocking errors.

---

## 2) Staff Entry Flow

- Sign in as role with staff entry access
- Open `/admin/supporters/new`
- Submit supporter
- Confirm supporter appears in list immediately

Pass if entry is saved and visible.

---

## 3) Supporter Detail + Audit

- Open supporter detail from list
- Confirm page loads in read-only by default
- If role can edit, click `Edit`, change field, save
- Confirm audit entry appears with readable field-level change
- If role cannot edit, confirm edit action is unavailable/blocked

Pass if behavior matches role expectations.

---

## 4) User Invite + First Login Flow

- As permitted role, invite a new user
- Confirm invite email received with "create account/sign up" guidance
- In fresh browser, create Clerk account with invited email
- Sign in and confirm user gets correct role-based access

Pass if no 403 loop or linking failure.

---

## 5) Navigation + Route Guarding

- For each role, confirm dashboard only shows allowed tools
- Manually paste one restricted route URL
- Confirm "Not Authorized" state appears

Pass if hidden + guarded behavior is consistent.

---

## 6) Election-Day Views (Current Scope)

- Open poll watcher page with allowed role
- Submit report for assigned precinct
- Confirm report appears in war room activity/metrics
- Confirm disallowed role cannot access these views

Pass if report pipeline works and permissions hold.

---

## 7) Smoke Quality Checks

- No infinite reload loops after login
- No major console/runtime errors
- Mobile layout is usable on key screens (`/admin`, supporters, users)

Pass if no blocking UX/functional regressions.

---

## Final Sign-Off

- RBAC checklist status: Pass / Fail
- Critical flow checklist status: Pass / Fail
- Blocking defects:
- Non-blocking defects:
- Recommended next fix batch:
