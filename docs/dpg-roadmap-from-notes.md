# DPG Roadmap From Notes And Transcripts

## Purpose

This document translates the Democratic Party of Guam notes/transcripts into a practical delivery roadmap. The deeper source-of-truth product plan lives in `docs/dpg-product-blueprint.md`.

The DPG platform is now a deployed voter-engagement foundation, not just a renamed campaign tracker. The important caveat is that the merged code has been reviewed and tested in the Rails/frontend test suite, but we have not completed a full deployed browser QA pass across the admin side yet.

## Sources reviewed

- Brain-Dump Democratic Party meeting transcript from April 2, 2026.
- Brain-Dump in-person meeting transcript from April 27, 2026.
- Brain-Dump DPG voter platform notes and implementation plan.
- Repo docs: `current-project-status.md`, `dpg-requested-feature-checklist.md`, `monday-testing-handoff.md`, and `clean-room-implementation-plan.md`.

## Implemented foundation

- Public DPG signup and thank-you flow.
- DPG-branded public pages.
- Unified `/admin` workspace with legacy `/data` and `/team` redirects.
- Contacts, Intake, classification, manual entry, search/filtering, reports, users, districts, precincts, and audit logs.
- Public signups and staff-entered records appear immediately as visible DPG contacts with `new_intake` classification, without inflating official supporter/member counts.
- CSV/Excel-style DPG contact import preview and confirm flow.
- Duplicate detection/review foundation.
- Staff users and role/scoped access foundation.
- GEC voter-list workspace with import/preview/activation, import history, voter search, address lookup, create-contact, and link-existing-contact workflows.
- Household/address workspace that cross-references GEC voters and DPG contacts by searched address.
- Structured contact history on contact detail for call, SMS, and in-person attempts.
- Follow-Up Queue latest-attempt summaries and inline call/SMS/in-person attempt logging.
- SMS/email configuration and compose screens.
- SMS/email recipient preview governance: live blasts require a dry run, sample review, and matching expected recipient count.
- SMS/email blast contact-attempt logging so blast attempts appear in contact history.
- Starter DPG message templates.

## Implemented, but needs deployed admin QA

The deployed site is online, but these admin workflows still need hands-on browser testing with real accounts and realistic data:

- Admin login, role permissions, and village-scoped access.
- Public signup to Intake/Contacts flow.
- Contacts list filters, sorting, classification updates, and exports.
- Manual entry and DPG contact import.
- Duplicate review.
- GEC spreadsheet import, preview, activation, search, and link/create-contact flows.
- Household/address lookup.
- Contact detail contact-attempt logging.
- Follow-Up Queue inline attempt logging.
- SMS and Email Center dry-run governance.
- Audit log visibility.
- Reports/export behavior.
- Mobile and tablet layouts for staff-facing pages.

## Still requested or likely needed

- Explicit import/list types for:
  - DPG contacts/supporters
  - DPG members
  - registered Democrat list
  - other custom lists
- DPG membership/supporter/registered-Democrat cross-reference reports against the GEC voter file.
- Clearer DPG-specific role names and permission descriptions.
- QR download/share workflow for field signup attribution.
- Support/need tracking beyond the current classification/contact-history foundation:
  - registration help
  - absentee ballot help
  - homebound voting help
  - ride to polls
  - volunteer follow-up
  - membership follow-up
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

1. Complete a deployed admin QA pass before inviting broad staff use:
   - public signup to Intake/Contacts
   - manual entry/import
   - GEC import/search/linking
   - household lookup
   - contact history
   - Follow-Up Queue
   - SMS/email dry runs
   - mobile layout
2. Create Auntie Stephanie's main admin account once she provides the preferred email address.
3. Finish the GEC import parity hardening pass after PR #31: large PDF progress/recovery, stale background jobs, skipped-row review, source-artifact review, import-diff review, and re-vetting status visibility.
4. Send a small tester handoff after QA, making clear that the site is ready for familiarization while we keep customizing it around DPG's workflow.
5. Build explicit list-type imports and cross-reference reports:
   - DPG contacts/supporters
   - DPG members
   - registered Democrat list
   - GEC match/unmatched reports
   - member/supporter registration status reports
6. Polish DPG roles and permissions so non-technical staff understand what each role can do.
7. Add QR field signup attribution and downloadable QR assets.
8. Expand support/need tracking and follow-up queues after DPG confirms the labels and workflow they want.
9. Scope the election-day module with DPG: poll watcher roles, voted/not-voted workflow, turnout dashboard, and war-room reporting.
10. Evaluate maps/heatmaps, autodialer integration, ID/photo intake, and OCR as separate add-ons after the core platform is trusted.
