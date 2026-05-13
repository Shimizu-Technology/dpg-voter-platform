# DPG Voter Platform - Current Project Status

**Last updated:** May 12, 2026  
**Current branch:** `main`  
**Current commit:** `547c4c7` - merged Phase 5 communications governance

## One-line status

The Democratic Party of Guam app is now deployed and has the core voter-engagement foundation in place: public signup, a unified admin workspace, Contacts/Intake, GEC voter-list search/import, household/address lookup, contact history, follow-up queue logging, reports, users/roles, and governed SMS/email outreach.

The important caveat is that most admin-side workflows have been verified through automated tests and code review, not through a full real-user browser smoke test on the deployed environment. Treat the deployed app as ready for guided internal QA/familiarization, not as fully production-validated for broad DPG operations yet.

## Product frame

DPG needs a party-wide voter engagement platform centered on:

- public GEC voter-file import/search
- DPG contacts, intake, members, supporters, volunteers, and prospects
- household/address canvassing
- contact history across SMS, email, calls, and in-person touches
- scoped roles for admins, staff, field users, and eventually poll watchers
- list cross-reference between GEC voters, DPG member rosters, registered Democrat lists, and supporter/contact data
- later Election Day turnout and war-room workflows designed with DPG

The app should keep using Shimizu Technology's reusable platform foundation, but the workflows should be shaped around DPG's needs instead of Josh/Tina-specific operating methods.

## Clean-room boundary

1. Shimizu Technology owns the reusable software/code/platform.
2. Josh/Tina own their campaign data, users, uploaded files, logs, and operating playbook.
3. DPG has a separate repo, deployment, database, auth setup, data, users, and workflow.
4. Reusable infrastructure is allowed; Josh/Tina data, branding, quota cadence, poll-watcher playbook, blue-sheet/OCR process, and campaign-specific reports are not.

## What DPG asked for

The April 2 and April 27 DPG notes/transcripts point to these needs:

- voter/supporter CRM
- DPG/member/supporter list import
- GEC/public voter-list search and cross-reference
- village/precinct/location organization
- address/household search for canvassing
- contact/canvassing history by method
- support/lean/donation/latest-notes tracking
- SMS and email outreach
- QR/mobile signup
- role and permission scoping for admins, party members, and field users
- poll watcher workflow by assigned precinct
- real-time voted/not-voted updates
- war-room/turnout visibility dashboard
- possible GIS/heatmaps later
- possible ID/photo/OCR import later
- possible autodialer integration later

## Implemented now

### DPG app foundation

- Dedicated DPG repo exists: `Shimizu-Technology/dpg-voter-platform`.
- DPG branding and public copy are active.
- DPG docs and clean-room guardrails exist.
- Active Josh/Tina branding/data/workflow surfaces have been removed or disabled.
- The app is deployed online, but deployment isolation details and full staging QA should still be checked against `docs/deployment-checklist.md`.

### Public signup and Intake

- Public landing/signup/thank-you flow exists.
- Public signup creates visible DPG contact records.
- Public signup, staff entry, and imported contacts default to `new_intake`.
- New records appear in Contacts and Intake immediately.
- New records do not count as official supporters/members until classified by staff.
- Local browser smoke testing previously covered landing, signup, village selection, submit, and thank-you redirect.
- Deployed public signup still needs a fresh staging smoke test after the latest merged phases.

### Unified admin workspace

- The active internal experience is `/admin`.
- Legacy `/data` and `/team` routes redirect into `/admin`.
- Sidebar navigation includes Dashboard, Contacts, Intake, GEC Voters, Households, New Entry, Import Contacts, Follow-Up, SMS Blasts, Email Blasts, Reports, Duplicates, Activity Log, Users, Districts, Precincts, and SMS/Public Settings.
- Admin-side pages are covered by route/API/tests, but most deployed browser workflows still need hands-on QA.

### Admin/staff access

- Clerk-backed admin/staff access exists.
- User management exists.
- Current highest-level role is still `campaign_admin`.
- Recommendation: create Auntie Stephanie as `campaign_admin` for now, then rename/reshape roles into DPG language in the next permissions polish phase.
- Users/roles, scoped permissions, and audit logs exist, but DPG role labels and export/delete restrictions still need product polish.

### Contacts and Intake CRM

- Contact list and contact detail exist.
- Contacts can be classified as:
  - new intake
  - active contact
  - supporter
  - member
  - volunteer
  - undecided
  - not supporting
  - duplicate
  - invalid
  - archived
- Manual staff entry exists.
- Search/filter basics exist, including name, phone, email, village, precinct, origin, opt-in, voter-check, classification, and address-style lookup.
- Village/precinct fields exist.
- Voter-help/support fields exist:
  - volunteer interest
  - absentee ballot help
  - homebound voting help
  - voter registration help
  - ride help
  - referral name
  - email/text opt-in

### Import/data workflow

- Contact CSV/Excel import preview/parse/confirm exists.
- Imported DPG contacts default to `new_intake`.
- Duplicate review/warnings exist.
- Reports/export basics exist.
- The current import flow is still generic; explicit list-type imports are not finished yet.

### GEC/public voter-list workspace

- GEC voter-list import/search is restored as a first-class DPG workspace.
- GEC data is treated as public voter-file infrastructure, not Josh/Tina proprietary data.
- Staff can search GEC voters by name, address, village, precinct, and voter registration number where present.
- Staff can inspect GEC household/address groupings.
- Staff can create DPG contacts from GEC voter records.
- Staff can link existing DPG contacts to GEC voter records from the GEC workspace.
- GEC import history/list-date handling exists.
- Richer GEC import QA screens for skipped rows, source artifacts, and import diffs are still deferred.
- After PR #31, run a parity hardening pass against the Josh/Tina campaign-tracker GEC importer: confirm large PDF progress/recovery, stale processing cleanup, skipped-row review, source-artifact access, and re-vetting status visibility before DPG relies on monthly production imports.

### Contact, household, and outreach operations

- Contact detail includes a structured Contact History timeline.
- Staff can log in-person, call, and SMS attempts with outcome, timestamp, note, and staff attribution.
- Contact-attempt logging is village-scoped through existing DPG contact permissions.
- `/admin/households` searches addresses across GEC voters and DPG contacts.
- `/admin/outreach` Follow-Up Queue shows latest contact attempt per card.
- Staff can log call/SMS/in-person attempts from queue cards without leaving the queue.

### SMS/email outreach

- SMS page exists.
- Email page exists.
- SMS/Public Settings page exists.
- SMS/email dry-run preview returns recipient count and sample recipients.
- Live SMS/email blasts require staff to preview first, confirm the recipient count, and submit a matching `expected_recipient_count`.
- Starter DPG templates exist for registration reminders, events/community updates, and volunteer follow-up.
- SMS/email blast jobs write structured `SupporterContactAttempt` rows for attempted recipients.
- SMS blast logging is guarded so contact-history failures do not mark successful sends as failed.
- Email blast job is guarded against retry-duplication after sends.
- DPG live outreach env is expected to be enabled only in the intended DPG environment.
- Real sends should only be tested with controlled DPG-approved recipients/content.

### Reports/export

- Reports API exists.
- Supporter/contact summary preview exists.
- Export basics exist.
- Existing reports are still inherited/generic in places; DPG-specific cross-reference reports are a next priority.

### Tests/checks

Latest merged PRs passed GitHub checks:

- `api_lint`
- `api_scan_ruby`
- `api_test`
- `web_lint_build`
- Greptile review

Latest local backend verification during Phase 5 review passed:

- Rails tests: `197 runs, 748 assertions, 0 failures`
- RuboCop: `194 files inspected, no offenses`
- Bundler audit: no vulnerabilities

## Still needs real deployed QA

We have not yet thoroughly browser-tested the deployed admin side. Before handing this to DPG as more than a familiarization build, run a guided deployed QA pass:

- public landing page
- public signup and thank-you
- admin login with DPG Clerk user
- Contacts list and Intake filter
- contact detail edit/classification
- contact-history logging
- manual entry
- contact CSV import preview/confirm
- duplicate review
- GEC voter import preview/upload/activate using a small safe file
- GEC voter search
- create DPG contact from GEC voter
- link existing DPG contact to GEC voter
- household/address lookup
- Follow-Up Queue latest-contact display and inline logging
- reports/export downloads
- users/roles mutations
- audit logs
- SMS/email dry-run recipient preview
- controlled single-recipient live SMS/email tests only when intentionally approved

## Intentionally deferred

These are important, but should be implemented deliberately:

- explicit list types:
  - GEC voter list
  - DPG contacts/supporters
  - DPG members
  - registered Democrat list
  - other/custom
- DPG membership roster vs GEC automation
- registered Democrat list import/cross-reference
- DPG contacts not matched to GEC report
- GEC voters marked supporter/member report
- members/supporters needing registration help report
- address/village mismatch reports
- support/lean/donation tracking
- DPG-specific district grouping
- role rename and permissions polish
- stronger export/delete restrictions for non-admin users
- richer canvassing route/assignment tooling beyond address search
- DPG-branded QR downloads/share links and attribution
- poll watcher workflow
- real-time voted/not-voted tracking
- war-room/turnout dashboard
- GIS/maps/heatmaps
- ID/photo/OCR scanning
- autodialer export/integration

## Recommended next work

Because the app is already deployed, the next move should not be another feature sprint immediately. The best next sequence is:

1. **Deployed admin QA pass**
   Confirm the admin side actually works end-to-end in the live environment, especially auth, mutations, imports, GEC workflows, reports, and outreach dry-runs.

2. **Create Auntie Stephanie's admin account**
   Use her preferred email and assign the current highest role, `campaign_admin`.

3. **Prepare a short DPG tester handoff**
   Tell DPG what to click first, what is safe to test, what not to live-send yet, and what feedback to send.

4. **Next product phase: list types + GEC/DPG cross-reference**
   Build explicit DPG member/supporter/registered-Democrat list imports and the reports that compare those lists against GEC voters.

5. **Permissions polish**
   Rename roles into DPG language and tighten export/delete/scope behavior for non-admin staff.

## Related docs

- `docs/dpg-product-blueprint.md` - source-of-truth DPG workflow and phased implementation plan.
- `docs/dpg-requested-feature-checklist.md` - DPG asks from transcripts mapped to product areas.
- `docs/deployment-checklist.md` - deployed environment and staging QA checklist.
- `docs/monday-testing-handoff.md` - now a general DPG tester handoff script despite the old filename.
- `docs/clean-room-implementation-plan.md` - boundary rules and cleanup rationale.
- `docs/proprietary-vs-reusable-review.md` - Josh/Tina vs reusable platform analysis.
