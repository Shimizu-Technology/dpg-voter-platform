# DPG Voter Platform - Current Project Status

**Last updated:** May 18, 2026
**Current branch:** `main`
**Base commit:** `fc96d72` after PR #37 merged DPG/GEC cross-reference reporting and Reports workspace polish

## One-line status

The Democratic Party of Guam app is deployed on the Render/Netlify/Neon stack and now has the core voter-engagement foundation in place: public signup, QR/share-link attribution, a unified admin workspace, Contacts/Intake, GEC voter-list search/import, household/address lookup, create/link contact actions from GEC and household results, contact history with editable audited corrections, follow-up queue logging, a redesigned Reports workspace with DPG/GEC cross-reference reports, users/roles, and governed SMS/email outreach.

Leon completed an initial production QA pass and confirmed the deployed app works. Auntie Stephanie has already been sent access and confirmed receipt. The next milestone is a guided in-person walkthrough with Auntie Stephanie when she returns from her trip, followed by DPG-provided list samples and workflow feedback before broad staff rollout.

## Product frame

DPG needs a party-wide voter engagement platform centered on:

- public GEC voter-file import/search
- DPG contacts, intake, supporters, volunteers, prospects, and future official member-roster cross-references
- household/address canvassing
- contact history across SMS, email, calls, and in-person touches
- scoped roles for admins, staff, field users, and eventually poll watchers
- list cross-reference between GEC voters, future official DPG member rosters, registered Democrat lists, and supporter/contact data
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
- DPG contact/supporter import and future official member-roster import
- GEC/public voter-list search and cross-reference
- village/precinct/location organization
- address/household search for canvassing
- contact/canvassing history by method
- support/volunteer/latest-contact tracking now, with support/lean/donation details to scope with DPG if they still want them
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
- The app is deployed online on the intended Render/Netlify/Neon stack.
- Live public URL currently used for review: `https://dpg-voter-platform.netlify.app/`.
- Live backend health and public API checks have been reported as passing, including Netlify-to-Render CORS and protected endpoint auth blocking.
- Leon completed a production QA pass and reported the core deployed flows working.

### Public signup and Intake

- Public landing/signup/thank-you flow exists.
- Public signup creates visible DPG contact records.
- Public signup, staff entry, and imported contacts default to `new_intake`.
- New records appear in Contacts and Intake immediately.
- New records do not count as supporters until reviewed and marked with support status by staff.
- Local browser smoke testing previously covered landing, signup, village selection, submit, and thank-you redirect.
- Deployed public signup has passed Leon's initial production QA. Keep it in the guided DPG walkthrough so Auntie Stephanie can confirm the language and intake expectations.

### Unified admin workspace

- The active internal experience is `/admin`.
- Legacy `/data` and `/team` routes redirect into `/admin`.
- Sidebar navigation includes Dashboard, Contacts, Intake, GEC Voters, Households, New Entry, Import Contacts, Follow-Up, SMS Blasts, Email Blasts, Reports, Duplicates, Activity Log, Users, Districts, Precincts, and SMS/Public Settings.
- Admin-side pages are covered by route/API/tests and Leon's initial production QA. They still need a guided DPG staff walkthrough before broad rollout.

### Admin/staff access

- Clerk-backed admin/staff access exists.
- User management exists.
- Current highest-level role is still stored as `campaign_admin` in the database, but the active UI now labels it as Administrator.
- Auntie Stephanie provided the preferred admin email on May 11: `Sgflores@gmail.com`.
- Access has been sent to Auntie Stephanie and she confirmed receipt.
- Users/roles, scoped permissions, and audit logs exist. Current DPG-facing labels are Administrator, Data Manager, Field Organizer, Village Coordinator, and Canvasser. Poll Watcher remains future work.
- Export is now limited to Administrator/Data Manager. Bulk contact import is limited to Administrator/Data Manager/Field Organizer. Canvassers and Village Coordinators can still work assigned-village contacts and log canvass/contact outcomes.
- Clerk sign-in reportedly still shows a development-mode label; acceptable for guided testing, but should be cleaned up before broad staff rollout.

### Contacts and Intake CRM

- Contact list and contact detail exist.
- Pending Intake has a structured reviewer workflow:
  - approve or reject intake
  - set record status as active contact, duplicate, invalid, or archived
  - separately set support status as not reviewed, supporter, undecided, or not supporting
  - separately set volunteer status as not reviewed, interested, active, or not interested
  - add reviewer note
  - optionally log the first outreach/contact outcome during review
  - audit the review decision
- Contact record lifecycle can be classified as:
  - new intake
  - active contact
  - duplicate
  - invalid
  - archived
- DPG relationship tracking is now split into separate fields:
  - support status: not reviewed, supporter, undecided, not supporting
  - volunteer status: not reviewed, interested, active, not interested
  - outreach/contacted status: derived from contact-attempt history, not from the relationship fields
- The legacy `membership_status` field still exists in the database/model and API contract for compatibility and future official member-roster work, but it is intentionally hidden from the active manual UI until DPG defines that roster workflow.
- Manual staff entry exists.
- QR/signup-link attribution is implemented: admins can create village/canvasser/outreach/custom signup links, copy/open them, scan generated QR codes, toggle active/inactive state, and view paginated signups per link.
- QR-attributed contacts retain the referral code/link relationship. Inactive links are ignored for new signups so stale printed links fall back to normal public signup attribution.
- Search/filter basics exist, including name, phone, email, village, precinct, origin, opt-in, voter-check, record status, support status, and address-style lookup.
- Village/precinct fields exist.
- Voter-help/support fields exist:
  - volunteer interest
  - absentee ballot help
  - homebound voting help
  - voter registration help
  - ride help
  - referral name
  - email/text opt-in
- Contact names, statuses, and linked GEC/contact references now use DPG-facing copy and link through to the contact detail page where practical.

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
- GEC voter and household results now surface linked contacts and likely DPG matches.
- Household lookup is now actionable: staff can create/link contacts from household search results.
- GEC possible-match review is clearer: Contact Detail can show ranked GEC match candidates, staff can confirm a specific shown GEC voter, and the app links that DPG contact to the official GEC record.
- Confirming a GEC match does **not** overwrite the DPG contact-entered name, phone, address, or village. It links the records and stores the official GEC voter relationship so the UI/reports can distinguish "DPG contact village/address" from "official GEC voter village/precinct/address."
- GEC import history/list-date handling exists.
- Async PDF preview/import support exists.
- Richer GEC import QA screens now exist for several import-review paths, but monthly production import confidence still needs live QA with real/safe files before DPG relies on it operationally.

### Contact, household, and outreach operations

- Contact detail includes a structured Contact History timeline.
- Staff can log in-person, call, and SMS attempts with outcome, timestamp, note, and staff attribution.
- Administrators and Data Managers can edit/correct contact attempts. Corrections are permission-gated, transactional, and audit logged with before/after data.
- Contact-attempt logging is village-scoped through existing DPG contact permissions.
- `/admin/households` searches addresses across GEC voters and DPG contacts.
- Address matching now uses `AddressNormalizer`, which collapses common street suffix variants, trailing Guam locality words, and PO Box variants so household grouping is less fragile.
- Household lookup can now create/link contacts from household results.
- Household DPG records now show the latest contact attempt or a clear Not contacted yet state, and can log a canvassing update directly from the household view.
- Household canvassing updates can set support/volunteer status and log method/outcome/note in one atomic action. Membership is intentionally not part of this manual canvass workflow.
- `/admin/outreach` Follow-Up Queue shows latest contact attempt per card.
- Staff can log call/SMS/in-person attempts from queue cards without leaving the queue.
- The Follow-Up Queue is for outreach work: registration outreach, voter-help requests, and volunteer follow-up. Possible GEC match review is intentionally handled through Intake/GEC Voters/Contact Detail voter-check workflows instead of this queue.
- Follow-up status sync now ties the two related workflows together without merging them: Contact History is the actual call/text/email/visit log, while registration and voter-help/volunteer follow-up fields are task outcome/progress lanes. Logging the first real contact attempt automatically starts untouched follow-up lanes when appropriate, but it does not mark registration or voter-help as resolved.
- Contact detail pages now include GEC check, follow-up workflow, latest-contact summary, contact history, audit history, record status, support status, QR attribution, and volunteer status.

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
- DPG/GEC list-intelligence and cross-reference reports now exist, including:
  - DPG contacts linked to GEC
  - DPG contacts not linked to GEC
  - GEC voters not in DPG contacts
  - possible GEC matches
  - DPG/GEC address or village mismatches
  - supporter list
  - referral list
  - village changes
  - mapping issues
  - purge list
- DPG/GEC contact cross-reference exports now include Contact ID, GEC Voter ID, origin/source attribution, campaign requests, suggested action, latest contact method, outcome, date, note, and official GEC voter fields where applicable.
- Cross-reference exports and previews now include separate record status, support status, and volunteer status columns. Membership should return here as an official member-roster signal once DPG defines that list workflow.
- The Reports page now uses a grouped report library, selected-report workspace, contextual filters, compact summary stats, and integrated preview/export actions.
- Explicit list-type imports are still needed so these reports can distinguish official DPG member rosters, registered Democrats, supporters/contacts, and custom lists cleanly.

### Tests/checks

Latest PR #37 validation before merge:

- GitHub `api_lint`: passing
- GitHub `api_scan_ruby`: passing
- GitHub `api_test`: passing
- GitHub `web_lint_build`: passing
- Greptile review: 5/5, safe to merge
- Local `cd api && bundle exec rails test`: passing
- Local `cd api && bundle exec rails zeitwerk:check`: passing
- Local `cd api && bundle exec rubocop`: passing
- Local `npm --prefix web run lint`: passing
- Local `npm --prefix web run build`: passing, with the existing Vite large chunk warning

Earlier reported validation:

- `api_lint`
- `api_scan_ruby`
- `api_test`
- `web_lint_build`
- Greptile review
- Rails test suite reported passing after local test DB reset: `227 runs, 906 assertions, 0 failures, 0 errors`.
- Live checks reported passing for Netlify public routes, Render `/up`, public campaign info API, protected endpoint auth, and CORS.

Previous local backend verification during Phase 5 review also passed RuboCop and Bundler audit.

## Still needs guided DPG QA

Leon has completed initial production QA and confirmed the app works on the deployed stack. Before broad DPG operations, run a guided walkthrough with Auntie Stephanie and a small DPG tester group:

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
- confirm Clerk production/development-mode configuration
- confirm database backup schedule before real operational data entry
- collect actual DPG list samples before building schema-specific importers beyond GEC and generic contact import

## Intentionally deferred

These are important, but should be implemented deliberately:

- explicit list types:
  - GEC voter list
  - DPG contacts/supporters
  - official DPG member rosters
  - registered Democrat list
  - other/custom
- official DPG member roster vs GEC automation
- registered Democrat list import/cross-reference
- richer list-lineage-aware report filtering after explicit list types exist
- support/lean/donation tracking
- DPG-specific district grouping
- any remaining permission tuning after DPG tests the role model
- richer canvassing route/assignment tooling beyond address search
- print-ready/downloadable QR assets beyond the current in-browser QR/share-link workflow
- poll watcher workflow
- real-time voted/not-voted tracking
- war-room/turnout dashboard
- GIS/maps/heatmaps
- ID/photo/OCR scanning
- autodialer export/integration

## Recommended next work

Because the app is already deployed and the QR/role/contact/household/reporting polish has merged, the next move should be guided DPG walkthrough plus list-sample discovery. The best next sequence is:

1. **Guided Auntie Stephanie walkthrough**
   Show the deployed app in person, walk through public signup, QR links, Contacts, Intake, GEC Voters, Households, Follow-Up, reports, users/roles, and SMS/email dry-runs. Capture what feels confusing in DPG language.

2. **Small DPG tester pass**
   Let a small DPG group test with fake/safe records before broad staff rollout. Confirm role scoping, import/export expectations, and which field users should see which villages.

3. **Collect real DPG list samples**
   DPG requested official member roster, registered Democrat, supporter/contact, and custom list cross-reference work. Do not build schema-specific importers until DPG provides actual files or sample columns. GEC import is the exception because we already have real GEC files.

4. **Next product phase: explicit list types + list-lineage reporting**
   Add DPG contacts/supporters, official member roster, registered Democrat, and custom list imports once samples exist. Then refine cross-reference reports so list origin, DPG support status, future official membership status, and GEC voter status are clear.

5. **Operational hardening**
   Confirm backups, Clerk production labeling, controlled live SMS/email, production import confidence, and any remaining role/delete/export concerns.

6. **Election Day discovery**
   Scope poll watcher, voted/not-voted, war-room reporting, and maps with DPG after they have used the foundation.

## Related docs

- `docs/dpg-product-blueprint.md` - source-of-truth DPG workflow and phased implementation plan.
- `docs/dpg-requested-feature-checklist.md` - DPG asks from transcripts mapped to product areas.
- `docs/deployment-checklist.md` - deployed environment and staging QA checklist.
- `docs/monday-testing-handoff.md` - now a general DPG tester handoff script despite the old filename.
- `docs/clean-room-implementation-plan.md` - boundary rules and cleanup rationale.
- `docs/proprietary-vs-reusable-review.md` - Josh/Tina vs reusable platform analysis.
