# DPG Voter Platform — Current Project Status

**Last updated:** May 11, 2026
**Current branch:** `phase-1-dpg-workflow-reset`

## One-line status

The Democratic Party of Guam app now has the Phase 1 DPG workflow reset in place: one internal workspace, visible Contacts, visible Intake, contact classification, and dashboard/session counts that no longer treat every public signup as an official supporter/member.

It can be used for internal testing/familiarization once a DPG admin account is created and the deployed/staging URL is confirmed, but the GEC voter-list workspace, household/address canvassing workflow, and contact-attempt history are still next-phase work.

## May 11 review note

This review reconciled the app with:

- Brain-Dump DPG transcripts from April 2 and April 27, 2026.
- Brain-Dump Josh/Tina notes, especially GEC import/runbook and UAT drafts.
- Current DPG route/UI/API surface.
- Current DPG docs and deployment checklist.

The updated product frame is:

> DPG needs a party-wide voter engagement platform centered on public GEC voter-file import/search, DPG contacts and intake, address/household canvassing, contact history, and outreach follow-up. Public signups and staff entries should be visible immediately, but they should not inflate official supporter/member counts until classified by DPG.

See `docs/dpg-product-blueprint.md` for the source-of-truth plan.

## Why we are building it this way

DPG asked for a party-wide voter engagement and election operations platform after seeing the existing campaign operations foundation.

The important boundary is:

1. Shimizu Technology owns the reusable software/code/platform.
2. Josh/Tina own their campaign data, users, uploaded files, logs, and operating playbook.
3. DPG should get a separate DPG app, deployment, database, auth setup, and workflow.
4. We can reuse generic platform capabilities, but we should not copy Josh/Tina-specific data, labels, reports, quota cadence, poll-watcher process, blue-sheet/OCR process, or campaign operating method.

So the project goal is not to delete every useful feature from the old foundation. The goal is to keep reusable infrastructure and rebuild DPG-specific workflows from DPG's own meeting requirements.

## What DPG asked for in meetings

DPG's requested platform includes:

- voter/supporter CRM
- DPG/member/supporter list import
- GEC/public voter-list search and cross-reference
- village/precinct/location organization
- ability to search by address / household / precinct / village
- contact/canvassing history by method: in-person, phone, email, phone bank
- support / lean / donation / latest notes tracking
- SMS and email outreach
- QR/mobile signup
- roles and permissions for admins, party members, and scoped field users
- poll watcher workflow by assigned precinct
- real-time voted/not-voted updates
- war-room / turnout visibility dashboard
- possible GIS/heatmaps later
- possible ID/photo/OCR import later

## What is done now

### Separate DPG app foundation

- Dedicated DPG repo exists: `Shimizu-Technology/dpg-voter-platform`.
- App is DPG-branded.
- DPG-specific docs and guardrails exist.
- Active Josh/Tina branding/data/workflow surfaces have been removed or disabled.
- Current tracked source is aligned with the DPG cleanup. Local git currently also shows an untracked root `package-lock.json`; decide whether to keep or delete it before the next commit.

### Public signup and Intake

- Public signup works.
- Thank-you flow works.
- Public signup creates a DPG contact record.
- Public signup records default to `new_intake`, appear immediately in Contacts and Intake, and do not count as official supporters/members until classified.
- Browser smoke test passed locally on May 11 against `http://127.0.0.1:5175`: landing page, signup form, village selection, submit, and thank-you redirect.
### One DPG internal workspace

- The active internal experience is `/admin`.
- Legacy `/data` and `/team` routes now redirect into `/admin`.
- Sidebar navigation now centers on Dashboard, Contacts, Intake, New Entry, Import Contacts, Follow-Up, Reports, and setup tools.

### Admin/staff access

- Clerk login works locally.
- Public staff portal and admin sign-in screens render locally after Clerk loads.
- Admin dashboard loads.
- User role authorization works.
- Users/roles page loads.
- Audit logs work.
- For Auntie Stephanie: collect her email and create her as `campaign_admin`, which is the highest-level role in the current app.

### Contact CRM

- Contact list works.
- Contact detail works.
- Contacts can be classified as new intake, active contact, supporter, member, volunteer, undecided, or not supporting.
- Manual staff entry works.
- The stale `/api/v1/staff/supporters` route was fixed to point at the existing staff-supporter controller; the frontend's current manual-entry path remains `/api/v1/supporters?entry_mode=staff&entry_channel=manual`.
- Staff-entered contacts are visible/searchable immediately and default to `new_intake`.
- Supporter search/filter basics exist, including name, phone, email, and street-address/household-style lookup.
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

- CSV import backend flow works.
- Imported contacts default to `new_intake` and are visible immediately.
- A new DPG readiness integration smoke test covers public signup, staff entry, session, supporter list, address/email search, duplicate scan, reports, audit logs, users, CSV import preview/parse/confirm, SMS status/dry-run, and email status/dry-run.
- Test import created supporter records successfully.
- Duplicate review/warnings work.
- Import UI exists, though final browser upload smoke test should still be repeated on staging.

### GEC/public voter-list foundation

- Guam village/precinct foundation exists.
- GEC/public voter-list matching/search foundation is preserved because it is generic and DPG-requested.
- GEC voter-list import/search should be restored as a first-class DPG workspace; it is public voter-file infrastructure, not Josh/Tina proprietary.
- The target workflow is address/name/village/precinct search against GEC, then link/create DPG contacts and record outreach/contact attempts.
- Josh/Tina quota/vetting semantics have been removed from active DPG surfaces.

### Reports/export

- Reports API works.
- Supporter summary preview works.
- Export basics exist.
- Inherited quota/turnout report surfaces have been removed from the Monday build.

### SMS/email outreach

- SMS page works.
- Email page works.
- SMS/settings page works.
- Dry-run/preview works.
- Live SMS/email provider credentials have been configured for DPG, and `DPG_LIVE_OUTREACH_ENABLED=true` is expected in the active DPG environment.
- Use dry-run/preview for normal smoke testing; run real sends only intentionally with DPG-approved recipients/content.
- Default sender identity is DPG-specific.

### Clean-room cleanup completed

The latest cleanup removed active inherited surfaces including:

- yard-sign/follow-up flag UI/API/blast filters
- inherited election-day turnout display/API fields from Monday-facing screens
- duplicate-merge dependency on event RSVP records
- static `campaign-tracker` metadata/cache keys
- active quota/war-room/poll-watcher/OCR routes and UI surfaces

Inactive implementation residue still exists in a few backend/support files, such as generic GEC PDF parsing, duplicate scanning, `EventRsvp`, and generic `campaign_*` service naming. These are not visible Monday-facing Josh/Tina workflows, but they should be reviewed before building any future DPG poll-watcher, OCR, event, or turnout module.

## What is intentionally deferred

These are not optional in the long-term DPG product, but should be implemented deliberately in the updated priority order:

- GEC voter-list import/search/address workspace
- DPG membership roster vs GEC automation
- multiple list types: GEC, registered Democrat list, DPG roster/supporter list
- fuller household/address workspace beyond the current street-address search and linked-household display
- structured contact attempt history
- support/lean/donation tracking
- DPG-specific district grouping
- precinct/village/district-scoped permissions
- poll watcher workflow
- real-time voted/not-voted tracking
- war-room / turnout dashboard
- GIS/maps/heatmaps
- ID/photo/OCR scanning
- autodialer integration
- live SMS/email blast governance, templates, and recipient approval flow

## What still needs to happen before Monday/staging

### Deployment setup

- Create isolated DPG backend service.
- Create isolated DPG frontend deployment.
- Create DPG-specific database.
- Create/use DPG-specific Clerk app and keys.
- Configure DPG-specific env vars/secrets.
- Confirm `FRONTEND_URL`, CORS, and API URLs.
- Configure backups before real testing data is entered.
- Share the deployed/staging URL with DPG only after confirming it points at DPG-specific services, database, Clerk keys, and environment variables.

### Final staging smoke test

Run on staging:

- public signup
- thank-you page
- admin login
- supporter list
- supporter detail
- manual entry
- search/filter
- CSV import preview/confirm
- duplicate review
- reports/export
- users/roles
- audit logs
- SMS/email dry-run
- live SMS/email configured; controlled live-send QA only when intentional

### Handoff prep

Prepare for DPG testers:

- login/access instructions
- what to test first
- known limitations
- intentionally deferred modules
- operating note that live outreach is configured and real sends should only be done intentionally
- note that election-day/poll-watcher/war-room tools are next-phase workflow design items

## Current recommendation

Use the current build as a testing foundation. The Phase 1 workflow reset is now in place, so DPG can start testing Contacts, Intake, imports, search, reports, users, audit logs, and outreach basics while the GEC voter-list workspace is implemented next.

Frame it as:

> “This is the DPG voter engagement foundation. Contacts and Intake are ready for testing now. The next pass adds the GEC voter-file search, address/household canvassing, contact history, and deeper outreach workflow.”

Do not frame it as a finished election-day command center yet.

## Verification already passed after latest cleanup

- frontend lint: passed on May 11
- frontend production build: passed on May 11; Vite warned that local Node 22.0.0 is below the recommended 22.12+ line
- Rails tests: passed on May 11 with rbenv Ruby 3.3.7 and Bundler 4.0.5: 173 runs, 656 assertions, 0 failures.
- Rails tests: passed on May 11 with rbenv Ruby 3.3.7 / Bundler 4.0.5; 173 runs, 645 assertions, 0 failures
- route/source review: no active DPG routes for inherited war-room, poll-watcher, quota, OCR form scan, yard-sign, or motorcade modules

## Related docs

- `docs/dpg-requested-feature-checklist.md` — what DPG asked for and Monday vs next phase.
- `docs/dpg-product-blueprint.md` — source-of-truth DPG workflow and phased implementation plan.
- `docs/clean-room-implementation-plan.md` — boundary rules and cleanup rationale.
- `docs/proprietary-vs-reusable-review.md` — Josh/Tina vs reusable platform analysis.
- `docs/dpg-remove-add-plan.md` — what to remove, keep, and add.
- `docs/monday-scope-and-confidence-audit.md` — Monday scope and verification gates.
- `docs/monday-testing-handoff.md` — tester handoff script and known deferred modules.
- `docs/deployment-checklist.md` — staging/deployment checklist.
