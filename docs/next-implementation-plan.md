# DPG Voter Platform - Next Implementation Plan

**Created:** May 14, 2026
**Last updated:** May 22, 2026
**Status:** Updated after PR #40 beta usability polish and PR #41 DPG quota/period foundation merged to `main`
**Base commit:** `43daeaa`

## Current posture

The DPG platform has completed its first live demo walkthrough with Auntie Stephanie and DPG team members. The demo went well: DPG understood the Intake/GEC/QR/household/duplicate workflows and began discussing real operational use with village organizers, signup contests, quotas/periods, Mike Weekly's poll-watcher team, and future list imports.

The app should now be treated as a controlled beta build for a small DPG tester group, not yet a broad staff rollout. PR #40 addressed the immediate beta usability polish around GEC/address search, QR-code downloads, signup-link lifecycle, and safe demo-data cleanup. PR #41 added the DPG-owned quota/period foundation. The remaining direct demo ask to implement next is SMS/email delivery visibility and resend-to-failed/undelivered recipients.

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
- Duplicate Contact Review for DPG contact cleanup, with persistent dismissed-pair history, grouped sidebar count, merge safeguards, and Intake approval blocking for unresolved duplicate warnings.
- Beta GEC/address search and QR/signup-link lifecycle polish from PR #40.
- DPG quota/period foundation from PR #41: period management, active-period attribution, dashboard/Signup Links/Reports/Contacts/Intake period filters, period drilldowns, realtime invalidation, and one-active-period safeguards.

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

### SMS/email delivery status and resend

The next product step should address the remaining concrete May 20 demo ask: DPG wants to see who received/did not receive outreach messages and resend only to failed/undelivered recipients.

Recommended next branch:

- add recipient-level delivery records for SMS and email blasts
- store ClickSend `message_id` and Resend email IDs per recipient
- ingest ClickSend delivery receipts via polling and/or delivery-receipt rules
- ingest Resend webhook events (`sent`, `delivered`, `delivery_delayed`, `failed`, `bounced`, `complained`, `suppressed`)
- show blast detail recipient/status tables
- add resend-only-failed/undelivered actions with safe contact-history logging
- keep live outreach gated behind existing preview/expected-recipient-count governance

DPG also confirmed that official active/inactive party lists exist, but schema-specific importers should still wait for actual DPG sample files.

## Next product phases

### 1. GEC search, address search, and beta usability polish

Status: merged in PR #40.

Implemented from demo feedback:

- punctuation-insensitive GEC voter search
- middle-initial tolerant search
- less strict GEC list view matching
- address normalization/search for PO Box/P.O. Box/HCR/HC variants
- QR-code download for signup links
- delete unused signup links; archive/deactivate used links
- safe archive/remove flow so demo contacts can sign up again later without poisoning future attribution or duplicate detection

### 2. DPG quota/period foundation

Status: merged in PR #41.

DPG independently raised quota/period needs during the demo, so this is now safe to design as a DPG-owned goals/period system rather than a copied campaign workflow.

Implemented scope:

- admin-defined quota/goal periods with start/end dates
- active period selection
- new public signups, QR signups, and staff entries attributed to the active period
- active-period summary on the dashboard
- period-aware signup-link counts with lifetime totals preserved
- reports that can filter by period
- Contacts/Intake period filters
- embedded period drilldown table with pagination
- realtime cache invalidation for period-related counts
- model/database safeguards for one active period
- duplicate handling remains in Duplicate Contact Review; more advanced unique-credit rules should wait for DPG feedback

Clarify before detailed dashboards:

- whether quotas count raw signups, approved contacts, supporters, registered Democrats, volunteers, or multiple metrics
- whether goals are per village, per user, per signup link, or party-wide
- how DPG wants to handle carryover between periods

### 3. SMS/email delivery status and resend

DPG asked to see who received/did not receive messages and to resend only to people who did not receive the first message.

Initial scope:

- per-recipient SMS and email delivery status storage
- blast detail recipient/status table
- failed/undelivered resend action
- ClickSend delivery receipt polling and/or delivery receipt rule support
- Resend webhook event ingestion and signature verification
- provider IDs stored per recipient so statuses can reconcile back to the original blast

### 4. DPG list imports and list lineage

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
