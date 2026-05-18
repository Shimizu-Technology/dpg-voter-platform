# DPG Roadmap From Notes And Transcripts

## Purpose

This document translates the Democratic Party of Guam notes/transcripts into a practical delivery roadmap. The deeper source-of-truth product plan lives in `docs/dpg-product-blueprint.md`.

The DPG platform is now a deployed voter-engagement foundation, not just a renamed campaign tracker. Leon completed an initial production QA pass on the Render/Netlify/Neon deployment, Auntie Stephanie has access and confirmed it, and the next checkpoint is a guided DPG workflow review before broad staff rollout.

## Sources reviewed

- Brain-Dump Democratic Party meeting transcript from April 2, 2026.
- Brain-Dump in-person meeting transcript from April 27, 2026.
- Brain-Dump DPG voter platform notes and implementation plan.
- Repo docs: `current-project-status.md`, `dpg-requested-feature-checklist.md`, `monday-testing-handoff.md`, and `clean-room-implementation-plan.md`.
- User/project decisions through May 18, 2026, including the decision to wait on non-GEC schema-specific imports until DPG provides actual list files or sample columns.

## Implemented foundation

- Public DPG signup and thank-you flow.
- DPG-branded public pages.
- Unified `/admin` workspace with legacy `/data` and `/team` redirects.
- Contacts, Intake, classification, manual entry, search/filtering, reports, users, districts, precincts, and audit logs.
- Public signups and staff-entered records appear immediately as visible DPG contacts with `new_intake` classification, without inflating supporter counts until reviewed.
- CSV/Excel-style DPG contact import preview and confirm flow.
- Duplicate detection/review foundation.
- Staff users and role/scoped access foundation.
- DPG-facing role labels: Administrator, Data Manager, Field Organizer, Village Coordinator, and Canvasser.
- Tighter permission boundaries: export is limited to Administrator/Data Manager, bulk import to Administrator/Data Manager/Field Organizer, QR links to field roles, and contact-attempt correction to Administrator/Data Manager.
- GEC voter-list workspace with import/preview/activation, import history, voter search, address lookup, create-contact, and link-existing-contact workflows.
- Possible GEC match candidate display before staff confirms a match.
- Household/address workspace that cross-references GEC voters and DPG contacts by searched address, with conservative address normalization for street suffixes and trailing locality text.
- Structured contact history on contact detail for call, SMS, email, and in-person attempts.
- Audited contact-attempt correction workflow for Administrator/Data Manager.
- QR/share signup attribution with source links, generated QR codes, active toggles, contact attribution, and per-link signup lists.
- Follow-Up Queue latest-attempt summaries, inline call/SMS/in-person attempt logging, and first-contact follow-up status sync.
- SMS/email configuration and compose screens.
- SMS/email recipient preview governance: live blasts require a dry run, sample review, and matching expected recipient count.
- SMS/email blast contact-attempt logging so blast attempts appear in contact history.
- Starter DPG message templates.

## Implemented, but needs guided DPG workflow QA

The deployed site is online and has had initial technical QA, but these workflows still need hands-on validation with Auntie Stephanie or a small DPG tester group:

- Admin login, role permissions, and village-scoped access.
- Public signup to Intake/Contacts flow.
- Contacts list filters, sorting, classification updates, and exports.
- Manual entry and DPG contact import.
- Duplicate review.
- GEC spreadsheet import, preview, activation, search, and link/create-contact flows.
- Household/address lookup.
- Contact detail contact-attempt logging and audited correction.
- QR/source-link creation, scanning/copying, active toggle, and per-link signup review.
- Follow-Up Queue inline attempt logging and follow-up outcome updates.
- SMS and Email Center dry-run governance.
- Audit log visibility.
- Reports/export behavior, including the grouped Reports workspace and DPG/GEC cross-reference reports.
- Mobile and tablet layouts for staff-facing pages.

## Still requested or likely needed

- Explicit import/list types for:
  - DPG contacts/supporters
  - official DPG member rosters
  - registered Democrat list
  - other custom lists
- Explicit official member-roster and registered-Democrat cross-reference reports against the GEC voter file once DPG provides real list samples.
- Current DPG/GEC contact cross-reference reports are implemented for linked contacts, unlinked contacts, GEC outreach gaps, possible matches, and DPG/GEC address/village/precinct mismatches.
- Membership is intentionally not an active manual classification right now. The legacy `membership_status` field remains in the backend for future official member-roster import/cross-reference work once DPG defines that workflow.
- Print-ready/downloadable QR assets after DPG tests the current QR/share-link workflow.
- Support/need tracking beyond the current classification/contact-history foundation:
  - registration help
  - absentee ballot help
  - homebound voting help
  - ride to polls
  - volunteer follow-up
  - official member-roster follow-up, once DPG defines that workflow
  - donation interest/follow-up if DPG wants it
- DPG-owned election-day module:
  - poll watcher workflow
  - precinct-scoped poll watcher accounts
  - voted/not-voted updates
  - turnout/call-list dashboard
  - war-room reporting
- GIS/maps/heatmaps.
- Autodialer export/integration after DPG chooses the provider.
- ID/photo intake.
- OCR/photo paper-form intake, rebuilt around DPG-defined forms/processes.
- DPG-defined district mapping if DPG wants districts beyond public village/precinct structure.

## Why the remaining pieces need deliberate implementation

- The April 27 transcript supports giving DPG a usable foundation first, then improving it with their real workflow once they can click through the deployed site.
- Election-day, OCR, quota-like, and poll-watcher modules are high-risk to copy directly from Josh/Tina because they can encode another campaign's operating method.
- DPG did ask for those concepts, but they should be rebuilt or configured from DPG's own process rather than inherited blindly.
- Live outreach now has a safer recipient-review gate, but legal language, suppression rules, opt-in review, sender approval, and deliverability still need operational review before broad production use.

## Recommended next order

1. Complete a guided DPG workflow walkthrough before inviting broad staff use:
   - public signup to Intake/Contacts
   - QR signup attribution
   - manual entry/import
   - GEC import/search/linking
   - possible-match confirmation
   - household lookup
   - household canvass logging
   - contact history and audited correction
   - Follow-Up Queue
   - SMS/email dry runs
   - mobile layout
2. Confirm production operational setup:
   - Clerk roles and invited users
   - database backup expectations
   - Render/Netlify environment variables
   - SMS/email sender approval and suppression policy before broad live sends
3. Collect real DPG list samples before schema-specific importer work:
   - DPG contacts/supporters
   - official DPG member rosters
   - registered Democrat list
   - any custom lists DPG already maintains
4. Build explicit list-type imports and list-lineage reports after samples exist:
   - DPG contacts/supporters
   - official DPG member rosters
   - registered Democrat list
   - member-roster and registered-Democrat match/unmatched reports
   - supporter and future member-roster registration status reports
5. Finish the GEC import parity hardening pass when needed: large PDF progress/recovery, stale background jobs, skipped-row review, source-artifact review, import-diff review, and re-vetting status visibility.
6. Polish QR print/download assets and field instructions after DPG tests the workflow.
7. Expand support/need tracking and follow-up queues after DPG confirms the labels and workflow they want.
8. Scope the election-day module with DPG: poll watcher roles, voted/not-voted workflow, turnout dashboard, and war-room reporting.
9. Evaluate maps/heatmaps, autodialer integration, ID/photo intake, and OCR as separate add-ons after the core platform is trusted.
