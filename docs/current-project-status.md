# DPG Voter Platform — Current Project Status

**Last updated:** May 9, 2026  
**Current commit:** `fb02556 DPG-16: Remove inherited campaign workflow surfaces`

## One-line status

The Democratic Party of Guam app is now a clean, Monday-testable voter engagement MVP built from Shimizu Technology's reusable platform foundation, with other-campaign data, branding, and active campaign-specific workflows removed from the starter build.

It is ready to move toward isolated DPG staging after final deployment setup, but it is not yet the full election-operations platform DPG described in the meetings.

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
- Current branch is pushed and clean.

### Public signup

- Public signup works.
- Thank-you flow works.
- Public signup creates a supporter/contact record.
- This covers the basic QR/mobile-signup foundation.

### Admin/staff access

- Clerk login works locally.
- Admin dashboard loads.
- User role authorization works.
- Users/roles page loads.
- Audit logs work.

### Supporter/contact CRM

- Supporter list works.
- Supporter detail works.
- Manual staff entry works.
- Staff-entered supporters now default to approved/searchable.
- Supporter search/filter basics exist.
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
- Test import created supporter records successfully.
- Duplicate review/warnings work.
- Import UI exists, though final browser upload smoke test should still be repeated on staging.

### GEC/public voter-list foundation

- Guam village/precinct foundation exists.
- GEC/public voter-list matching/search foundation is preserved because it is generic and DPG-requested.
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
- Live SMS/email sending is blocked unless `DPG_LIVE_OUTREACH_ENABLED=true` is explicitly approved.
- Default sender identity is DPG-specific.

### Clean-room cleanup completed

The latest cleanup removed active inherited surfaces including:

- yard-sign/follow-up flag UI/API/blast filters
- inherited election-day turnout display/API fields from Monday-facing screens
- duplicate-merge dependency on event RSVP records
- static `campaign-tracker` metadata/cache keys
- active quota/war-room/poll-watcher/OCR routes and UI surfaces

## What is intentionally deferred

These were requested or discussed by DPG, but should not be rushed into Monday unless separately scoped/tested:

- DPG membership roster vs GEC automation
- multiple list types: GEC, registered Democrat list, DPG roster/supporter list
- household/address lookup
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
- live SMS/email blasts

## What still needs to happen before Monday/staging

### Deployment setup

- Create isolated DPG backend service.
- Create isolated DPG frontend deployment.
- Create DPG-specific database.
- Create/use DPG-specific Clerk app and keys.
- Configure DPG-specific env vars/secrets.
- Confirm `FRONTEND_URL`, CORS, and API URLs.
- Configure backups before real testing data is entered.

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
- live SMS/email blocked unless approved

### Handoff prep

Prepare for DPG testers:

- login/access instructions
- what to test first
- known limitations
- intentionally deferred modules
- warning that live blasts are disabled unless explicitly approved
- note that election-day/poll-watcher/war-room tools are next-phase workflow design items

## Current recommendation

Use this as the Monday testing build for the core voter engagement/admin foundation.

Frame it as:

> “This is the DPG voter engagement foundation: signup, CRM, import, search/filter, roles, reports, audit logs, and safe SMS/email preview. The election-day operations layer — poll watchers, voted/not-voted tracking, war room, household canvassing, and maps — should be designed with DPG after they validate the core workflow.”

Do not frame it as a finished election-day command center yet.

## Verification already passed after latest cleanup

- frontend lint
- frontend production build
- frontend TypeScript build
- Ruby syntax checks
- Rails zeitwerk check
- source scan for active Josh/Tina/quota/war-room/poll-watcher/yard-sign/event-rsvp residue

## Related docs

- `docs/dpg-requested-feature-checklist.md` — what DPG asked for and Monday vs next phase.
- `docs/clean-room-implementation-plan.md` — boundary rules and cleanup rationale.
- `docs/proprietary-vs-reusable-review.md` — Josh/Tina vs reusable platform analysis.
- `docs/dpg-remove-add-plan.md` — what to remove, keep, and add.
- `docs/monday-scope-and-confidence-audit.md` — Monday scope and verification gates.
- `docs/monday-testing-handoff.md` — tester handoff script and known deferred modules.
- `docs/deployment-checklist.md` — staging/deployment checklist.
