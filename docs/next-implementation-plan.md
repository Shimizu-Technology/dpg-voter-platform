# DPG Voter Platform - Next Implementation Plan

**Created:** May 14, 2026
**Last updated:** May 18, 2026
**Status:** Updated after PR #37 reporting polish merged to `main`
**Base commit:** `fc96d72`

## Current posture

The DPG platform is deployed and ready for guided review with Auntie Stephanie and a small tester group. Leon has completed initial production QA on the Render/Netlify/Neon deployment and Auntie Stephanie has already received and confirmed access.

The app should still be framed as a guided review build, not a broad staff rollout. The foundation works, but DPG still needs to validate the language, role model, list workflows, and field process in person.

Already in place:

- DPG-branded public site and signup.
- QR/share-link attribution with active/inactive source links and per-link signup lists.
- Clerk-protected staff/admin workspace.
- Contacts and Intake.
- GEC voter import/search.
- GEC-to-contact create/link workflows.
- Contact detail voter-check workflow with ranked GEC candidates and specific-match confirmation.
- Household/address lookup with create/link actions and conservative address normalization.
- Contact detail with relationship classification, GEC check, follow-up lanes, contact history, editable audited contact-attempt corrections, and audit history.
- Follow-Up Queue for registration, voter-help, and volunteer follow-up, connected to Contact History.
- SMS/email dry-run governance, starter templates, and contact-history logging.
- Redesigned Reports workspace, including DPG/GEC cross-reference reports and mismatch reporting.
- DPG-facing role labels and tightened import/export/contact-attempt permissions.

## Before broader DPG rollout

1. Walk Auntie Stephanie through the live app in person when she returns from her trip.
2. Confirm Clerk production-mode settings and database backup schedule before DPG enters real operational data.
3. Run a small DPG tester pass using safe records:
   - public signup and QR signup to Intake/Contacts
   - manual entry
   - contact import
   - duplicate review
   - GEC import/search/link/create-contact
   - GEC match candidate confirmation
   - household lookup and household canvass logging
   - contact detail classification and contact-history logging/correction
   - Follow-Up Queue logging and follow-up lane updates
   - reports/exports
   - users/roles
   - audit log
   - SMS/email dry runs
4. Collect actual DPG list samples before building list-specific importers beyond GEC and generic contact import.
5. Update tester handoff language based on where Auntie Stephanie and DPG testers get confused.

## Next product recommendation

### Guided DPG Walkthrough + List-Sample Intake

The next product step is not another speculative importer. DPG did ask for official member rosters, registered Democrat lists, supporter/contact lists, and cross-reference reporting in the April meetings, but we should wait for real list files or sample columns before building schema-specific mapping.

The recommended next branch after the walkthrough should be based on what DPG gives us:

- If they bring real list files, build explicit list types and list-lineage reporting.
- If they find workflow confusion first, polish language, role scoping, follow-up labels, or household/GEC review flow.
- If they are ready to prepare field use, polish QR print/download assets, field instructions, and small-team permissions.

## Next product phases

### 1. DPG list imports and list lineage

Build first-class import types only after DPG provides files or sample schemas:

- DPG contacts/supporters
- official DPG member roster
- registered Democrat list
- other/custom lists

Track:

- list type
- import batch
- source file/name
- imported by
- import date
- GEC match state
- whether the imported person became a contact, supporter, volunteer, intake record, or future official member-roster match

Important constraint: GEC import is already first-class because we have real GEC list files. Other DPG list importers should wait until DPG gives us the actual list shapes.

### 2. Cross-reference reporting polish

Already present:

- DPG/GEC cross-reference reports for linked contacts, unlinked contacts, GEC voters not in DPG contacts, possible GEC matches, and DPG/GEC address/village/precinct mismatches.
- Latest contact method, outcome, date, and note in cross-reference exports.
- Contact ID, GEC Voter ID, source/origin, campaign requests, suggested action, official GEC voter fields where applicable, and separate DPG record/support/volunteer statuses.
- Grouped Reports workspace with contextual filters and integrated preview/export actions.

Still refine after explicit list types:

- official DPG member-roster records not found on GEC list
- registered Democrats not in DPG contacts
- registered Democrat/supporter/member-roster overlap
- list-origin and list-date reporting
- supporters and future official member-roster records needing registration help

### 3. Household canvassing workflow

Implemented now:

- Household search shows GEC voters and DPG contacts separately.
- DPG contacts at a household show latest contact state.
- Staff can log a canvassing/contact outcome directly from household results.
- Staff can update support/volunteer status from the household view.
- Address normalization groups common variants like Ave/Avenue, St/Street, punctuation, PO Box variants, and trailing village/locality text without changing the raw stored address.

Still worth doing later:

- admin-reviewed possible same-address handling before any destructive merge
- "I am at this address" field mode
- household-level canvass session/route context
- field assignment/route lists if DPG wants structured walk packets

### 4. QR and attribution

Implemented now:

- public signup
- village/canvasser/outreach/custom source links
- in-browser QR generation
- copy/open controls
- active/inactive toggles
- paginated signup lists per link
- contact detail/list attribution so staff can see QR-origin signups clearly

Future polish:

- print-ready/downloadable QR assets
- event-specific labels/templates
- DPG-approved naming conventions after live testing

### 5. Roles and permissions

Current DPG-facing roles:

- Administrator
- Data Manager
- Field Organizer
- Village Coordinator
- Canvasser
- Poll Watcher later

Implemented permission posture:

- export: Administrator/Data Manager only
- bulk contact import: Administrator/Data Manager/Field Organizer only
- QR/signup-link access: available to scoped field roles
- household canvass/contact logging: available to assigned field users in scope
- contact-attempt correction: Administrator/Data Manager only, with audit trail
- membership UI hidden from active manual workflows and reserved for future official roster/list handling

Still future:

- optional contact-attempt void/cancel workflow if DPG needs invalidation without deleting history
- final delete/archive permission review
- poll watcher role
- precinct-specific Election Day access rules

### 6. Election-day scope

Do not copy Josh/Tina election-day workflows directly. Scope this with DPG first.

Likely build:

- poll watcher role
- assigned precinct access
- fast voter checkoff
- real-time voted/not-voted tracking
- turnout dashboard
- war-room/call-list view
- audit trail for turnout changes

### 7. Later add-ons

- GIS/maps/heatmaps
- ID/photo intake
- OCR paper-form intake based on DPG-defined forms
- autodialer export or integration
- advanced analytics

## Communication posture

When sharing the link with DPG, call it a guided review build:

- It is deployed and ready for Stephanie to review.
- Auntie Stephanie already has access.
- It is ready for structured feedback.
- It is not the final DPG operating workflow yet.
- The goal is to walk through it together, decide what needs updating before go-live, collect real list files, and then launch with ongoing updates or refine first.
