# DPG Voter Platform - Next Implementation Plan

**Created:** May 14, 2026
**Status:** Updated after intake/relationship/household/report polish branch
**Base commit:** `f8f3d97`

## Current posture

The DPG platform is ready for guided review and familiarization with Auntie Stephanie and a small tester group. It is not yet a broad production rollout.

The foundation is in place:

- DPG-branded public site and signup.
- Clerk-protected staff/admin workspace.
- Contacts and Intake.
- GEC voter import/search.
- GEC-to-contact create/link workflows.
- Household/address lookup with create/link actions.
- Contact detail with classification, GEC check, follow-up workflow, contact history, and audit history.
- Follow-Up Queue with inline contact logging.
- SMS/email dry-run governance, starter templates, and contact-history logging.
- Reports, including DPG/GEC cross-reference reports.
- Users, roles, districts, precincts, settings, and audit logs.

The immediate goal is to turn the working foundation into a workflow DPG can confidently use.

## Before broader DPG rollout

1. Create Auntie Stephanie admin access using `Sgflores@gmail.com`.
2. Run a live admin QA walkthrough with a real DPG admin session:
   - public signup to Intake/Contacts
   - manual entry
   - contact import
   - duplicate review
   - GEC import/search/link/create-contact
   - household lookup and household actions
   - contact detail classification and contact-history logging
   - Follow-Up Queue logging
   - reports/exports
   - users/roles
   - audit log
   - SMS/email dry runs
3. Confirm Clerk is configured for production before broader staff use.
4. Confirm database backup schedule before DPG enters real operational data.
5. Update tester handoff language based on the walkthrough.

## Next PR recommendation

### Intake Review + Relationship Status Polish

This was the most important next implementation step because it clarifies how a person moves from raw intake into DPG's working contact/supporter universe.

Built on `feature/intake-relationship-household-polish`:

- A clear Intake reviewer flow.
- Approve/reject actions.
- Mark record lifecycle as active contact, duplicate, invalid, or archived.
- Track support status separately as not reviewed, supporter, undecided, or not supporting.
- Track volunteer status separately as not reviewed, interested, active, or not interested.
- Keep contacted/not-contacted status derived from contact-attempt history.
- Keep the legacy `membership_status` backend field reserved for future official member-roster imports/cross-reference, but hide it from the active manual UI until DPG defines that workflow.
- Link out to the full GEC match review context from the intake review dialog.
- Surface current/possible GEC match status in the review context.
- Add optional initial note/contact outcome during review.
- Make official supporter/volunteer counts depend on relationship fields, not just record existence.
- Ensure audit logs capture review decisions.

Implemented acceptance criteria:

- A new public signup lands in Intake.
- Reviewer can classify it without leaving the review workflow.
- Reviewer can open the full record to confirm/link GEC match.
- Rejected/invalid/duplicate records stop appearing as normal working contacts.
- Supporter/volunteer counts only include records marked with those relationship statuses.
- DPG terminology is clear to non-technical staff.

Still worth polishing later:

- Inline GEC match confirmation directly inside the intake dialog.
- More guided duplicate merge handling inside the intake dialog.

## Next product phases

### 1. DPG list imports and list lineage

Build first-class import types:

- DPG contacts/supporters
- official DPG member rosters
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

### 2. Cross-reference reporting polish

Partially completed on `feature/intake-relationship-household-polish`:

- DPG/GEC cross-reference reports now include latest contact method, outcome, date, and note.

Still refine reports around DPG list types:

- official DPG member-roster records not found on GEC list
- registered Democrats not in DPG contacts
- DPG contacts not linked to GEC
- GEC voters with linked DPG contact
- possible GEC matches needing review
- supporters and future official member-roster records needing registration help
- address/village mismatches

### 3. Household canvassing workflow

Partially completed on `feature/intake-relationship-household-polish`:

- Household search shows latest contact attempt for DPG records.
- Staff can log a canvassing/contact outcome directly from household results.
- Staff can update support/volunteer status from the household view.

Still turn household search into a fuller field action:

- "I am at this address" mode.
- Show GEC voters and DPG contacts at the address.
- Add follow-up needs from the household view.
- Add household-level canvass session/route context.

### 4. QR and attribution

Implemented on PR #35 as the first usable slice:

- public signup
- village/canvasser/outreach/custom source links
- in-browser QR generation
- copy/open controls
- active/inactive toggles
- paginated signup lists per link
- contact detail/list attribution so staff can see QR-origin signups clearly

Future polish can add print-ready downloads, event-specific templates, and DPG-approved naming conventions after they test it.

### 5. Roles and permissions polish

Current branch `codex/dpg-role-contact-workflow-polish` implements the first pass:

- Main Admin
- Data Manager
- Field Organizer
- Village Coordinator
- Canvasser
- Poll Watcher later

Tightened in this branch:

- export permissions: Main Admin/Data Manager only
- contact import permissions: Main Admin/Data Manager/Field Organizer only
- QR/signup-link access: field roles can create/use scoped links
- household canvass logging: assigned field users can log method/outcome/note and update support/volunteer status in their scope
- membership remains hidden from active manual workflows and reserved for future official roster/list handling

Still future:

- delete/archive permission review
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

- It is ready for Stephanie to click around.
- It is ready for feedback.
- It is not the final DPG operating workflow yet.
- The goal is to walk through it together, decide what needs updating before go-live, and then either launch with ongoing updates or refine first.
