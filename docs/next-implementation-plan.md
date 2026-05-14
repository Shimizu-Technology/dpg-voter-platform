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

This was the most important next implementation step because it clarifies how a person moves from raw intake into DPG's working contact/member/supporter universe.

Built on `feature/intake-relationship-household-polish`:

- A clear Intake reviewer flow.
- Approve/reject actions.
- Mark record lifecycle as active contact, duplicate, invalid, or archived.
- Track support status separately as unknown, supporter, undecided, or not supporting.
- Track membership separately as not a member or member.
- Track volunteer status separately as unknown, interested, active, or not interested.
- Keep contacted/not-contacted status derived from contact-attempt history.
- Link out to the full GEC match review context from the intake review dialog.
- Surface current/possible GEC match status in the review context.
- Add optional initial note/contact outcome during review.
- Make official supporter/member/volunteer counts depend on relationship fields, not just record existence.
- Ensure audit logs capture review decisions.

Implemented acceptance criteria:

- A new public signup lands in Intake.
- Reviewer can classify it without leaving the review workflow.
- Reviewer can open the full record to confirm/link GEC match.
- Rejected/invalid/duplicate records stop appearing as normal working contacts.
- Supporter/member/volunteer counts only include records marked with those relationship statuses.
- DPG terminology is clear to non-technical staff.

Still worth polishing later:

- Inline GEC match confirmation directly inside the intake dialog.
- More guided duplicate merge handling inside the intake dialog.

## Next product phases

### 1. DPG list imports and list lineage

Build first-class import types:

- DPG contacts/supporters
- DPG members
- registered Democrat list
- other/custom lists

Track:

- list type
- import batch
- source file/name
- imported by
- import date
- GEC match state
- whether the imported person became a contact, member, supporter, volunteer, or intake record

### 2. Cross-reference reporting polish

Partially completed on `feature/intake-relationship-household-polish`:

- DPG/GEC cross-reference reports now include latest contact method, outcome, date, and note.

Still refine reports around DPG list types:

- DPG members not found on GEC list
- registered Democrats not in DPG contacts
- DPG contacts not linked to GEC
- GEC voters with linked DPG contact
- possible GEC matches needing review
- members/supporters needing registration help
- address/village mismatches

### 3. Household canvassing workflow

Partially completed on `feature/intake-relationship-household-polish`:

- Household search shows latest contact attempt for DPG records.
- Staff can log a canvassing/contact outcome directly from household results.
- Staff can update support/member/volunteer status from the household view.

Still turn household search into a fuller field action:

- "I am at this address" mode.
- Show GEC voters and DPG contacts at the address.
- Add follow-up needs from the household view.
- Add household-level canvass session/route context.

### 4. QR and attribution

Build DPG-branded QR/share links for:

- public signup
- events
- canvassers
- villages/precincts
- outreach pushes

Track source attribution on contacts.

### 5. Roles and permissions polish

Rename and tune roles into DPG language:

- Main Admin
- Data Manager
- Staff
- Field Organizer
- Canvasser
- Poll Watcher later

Tighten:

- export permissions
- delete/archive permissions
- village/precinct scoping
- user management access

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
