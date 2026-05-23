# DPG Voter Platform - Next Implementation Plan

**Created:** May 14, 2026
**Last updated:** May 23, 2026
**Status:** Updated after PR #43 outreach delivery/resend and PR #44 intake review/error handling polish merged to `main`
**Base commit:** `e0ceb08`

## Current posture

The DPG platform has completed its first live demo walkthrough with Auntie Stephanie and DPG team members. The demo went well: DPG understood the Intake/GEC/QR/household/duplicate workflows and began discussing real operational use with village organizers, signup contests, quotas/periods, Mike Weekly's poll-watcher team, and future list imports.

The app should now be treated as a controlled beta build for a small DPG tester group, not yet a broad staff rollout. PR #40 addressed the immediate beta usability polish around GEC/address search, QR-code downloads, signup-link lifecycle, and safe demo-data cleanup. PR #41 added the DPG-owned quota/period foundation. PR #43 implemented SMS/email delivery visibility and resend-to-failed/undelivered recipients. PR #44 fixed intake review stale-row/error visibility issues found during local testing and polished the email blast testing flow.

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
- SMS/email dry-run governance, starter templates, contact-history logging, recipient delivery status, provider receipt/webhook tracking, and failed-only resend.
- Redesigned Reports workspace, including DPG/GEC cross-reference reports and mismatch reporting.
- DPG-facing role labels and tightened import/export/contact-attempt permissions.
- Duplicate Contact Review for DPG contact cleanup, with persistent dismissed-pair history, grouped sidebar count, merge safeguards, and Intake approval blocking for unresolved duplicate warnings.
- Beta GEC/address search and QR/signup-link lifecycle polish from PR #40.
- DPG quota/period foundation from PR #41: period management, active-period attribution, dashboard/Signup Links/Reports/Contacts/Intake period filters, period drilldowns, realtime invalidation, and one-active-period safeguards.
- Intake review conflict/error feedback from PR #44: pending-only Intake queries, inline modal errors, approved-intake data repair, and Guam phone normalization for ClickSend.

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
   - SMS/email dry runs, delivery status refresh, and failed-only resend using controlled recipients/fake failures first
4. Confirm production outreach settings before any real SMS/email use: `DPG_LIVE_OUTREACH_ENABLED`, ClickSend credentials, Resend sender/domain, and `RESEND_WEBHOOK_SIGNING_SECRET`.
5. Collect actual DPG list samples before building list-specific importers beyond GEC and generic contact import.
6. Update tester handoff language based on where Auntie Stephanie and DPG testers get confused.

## Next product recommendation

### Guided beta, production hardening, and Election Day discovery

The direct May 20 demo asks around GEC/address search, QR link lifecycle, quota/periods, and SMS/email delivery/resend are now implemented. The next work should shift from feature catch-up to controlled operational validation and DPG-specific Phase 2 discovery.

Recommended next sequence:

1. **Guided DPG beta testing**
   Walk Auntie Stephanie and a small tester group through safe records across Intake, Contacts, GEC, Households, Duplicates, Reports, SMS/email dry runs, delivery status, and failed-only resend.

2. **Production readiness**
   Confirm DPG-specific Render/Netlify/Neon/Clerk services, backups, domain/CORS, live outreach credentials, Resend webhook secret, and Clerk production-mode settings.

3. **Election Day / poll-watcher implementation**
   Use the adjacent `campaign-tracker` poll watcher/war-room implementation as the technical blueprint, but adapt it to DPG language, permissions, and operations. Start with a conservative Poll Watcher MVP, then add the DPG Election Day Dashboard. See `docs/poll-watcher-implementation-plan.md` for the detailed review and plan.

4. **Real DPG list samples**
   Collect active list, inactive list, official member roster, registered Democrat list, and supporter/contact file samples before schema-specific list importers.

5. **Deferred add-on discovery**
   GIS/maps/heatmaps, OCR/photo intake, ID scanning, and autodialer integration remain valid ideas, but should be scoped only after DPG confirms real operational need and data/process constraints.

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

Status: merged in PR #43, with email UI/refresh and ClickSend Guam-phone polish in PR #44.

Implemented scope:

- per-recipient SMS and email delivery status storage
- provider message IDs for ClickSend and Resend
- SMS blast delivery table and ClickSend receipt sync
- Email blast delivery table and Resend webhook ingestion
- failed/undelivered/bounced/delayed/suppressed/unknown resend actions
- idempotent resend tracking through `outreach_deliveries`
- live send governance remains preview/count-confirmation gated

Still needs QA:

- controlled real-provider SMS test
- controlled real-provider email test
- Resend webhook production configuration
- staff confirmation that the status/resend UI is understandable

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

### 6. Election Day / poll-watcher scope

Status: recommended next major build. The `campaign-tracker` app has a mature implementation that is legitimate to use as a technical blueprint because DPG explicitly requested poll watcher, voted/not-voted, and war-room workflows. The DPG implementation must still use DPG-specific language, roles, visibility rules, and dashboard assumptions.

Recommended build sequence:

- PR 1: Poll Watcher MVP with role, precinct assignments, active election-day GEC list, mobile voter search/checkoff, turnout audit logging, and observed-elsewhere handling
- PR 2: DPG Election Day Dashboard with village/precinct turnout, not-yet-voted linked DPG supporters, ride-to-polls requests, exceptions, and recent poll watcher activity
- PR 3: user assignment/admin polish for Poll Watcher role and multiple precinct assignments
- PR 4: training/test mode and DPG/Mike Weekly handoff checklist

See `docs/poll-watcher-implementation-plan.md` for the detailed plan.

### 7. Later add-ons

- GIS/maps/heatmaps after address/geocoding quality and DPG map use cases are confirmed
- ID/photo intake after DPG defines what ID/photo data should be captured and who may access it
- OCR paper-form intake based on DPG-defined forms, not Josh/Tina blue-sheet assumptions
- autodialer export or integration after DPG names the tool/process
- advanced analytics after list types and Election Day data model are clearer

## Communication posture

When sharing the link with DPG, call it a guided review build:

- It is deployed and ready for Stephanie to review.
- Auntie Stephanie already has access.
- It is ready for structured feedback.
- It is not the final DPG operating workflow yet.
- The goal is to walk through it together, decide what needs updating before go-live, collect real list files, and then launch with ongoing updates or refine first.
