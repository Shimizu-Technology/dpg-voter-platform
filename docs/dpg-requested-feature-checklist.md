# DPG Requested Feature Checklist

**Purpose:** Track what DPG requested and convert it into the proper DPG platform plan. The current app should be treated as a starter foundation; the next work should follow `docs/dpg-product-blueprint.md`.

**Sources reviewed:**

- `Democratic-Party/1) - In Person meeting with Auntie Stephanie and Ethan - April 27, 2026.md`
- `Democratic-Party/2) - Democratic Pary Meeting with Mrs. Stephanie and her team - April 2nd, 2026.md`
- `Democratic-Party/3) Demoing app with the Democratic Party.md`

**Current implementation note, May 22, 2026:** The foundation, QR attribution, GEC search/linking, household lookup, role labels/permissions, contact history, editable contact-attempt corrections, follow-up lane sync, Duplicate Contact Review, redesigned Reports workspace, DPG/GEC cross-reference reports, beta search/usability polish, and DPG quota/period foundation are now merged to `main` through PR #41. Leon completed initial production QA and the first live DPG demo walkthrough. Auntie Stephanie and DPG team members validated the platform direction and surfaced concrete beta polish needs: less strict GEC search, better address matching, QR-code downloads, signup-link cleanup, safe demo-contact cleanup, SMS delivery/resend visibility, and DPG-owned quota/period tracking. The next implementation item is SMS/email delivery status and resend. The next unknown is not whether DPG wants list imports; they confirmed active/inactive party lists exist. The unknown is the exact shape of those files, so schema-specific list import work should wait for real DPG samples.

## What DPG clearly asked for

### 1. DPG contacts / voter engagement CRM

DPG asked for a voter information / CRM-style system where data can be uploaded, sorted, searched, and managed.

Core requirement:

- contact list
- contact detail page
- create/edit contact
- basic search/filter
- record lifecycle/status: new intake, active contact, duplicate, invalid, archived
- support status: not reviewed, supporter, undecided, not supporting
- volunteer status: not reviewed, interested, active, not interested
- contacted/not-contacted status from contact/follow-up history
- contact/follow-up history
- export basics
- latest contact summary on list/detail views
- audited contact-attempt correction for admins/data managers
- QR/signup source attribution where relevant

Important distinction:

- A DPG contact is not automatically a supporter.
- Public signups and staff entries should be visible immediately, but should go through Intake/classification before they inflate supporter counts.
- DPG discussed member lists/party membership rosters, but the meetings did not define membership as a separate manual staff classification. The legacy `membership_status` field remains in the database/model for future official member-roster import or cross-reference work and is intentionally hidden from the active UI until that workflow is defined.

### 2. DPG Intake queue

DPG needs a simple visible review/classification workspace. This is not the inherited Josh/Tina public-review/supporter-review flow.

Core requirement:

- public signups appear in Intake
- staff/manual entries can appear in Intake when unclassified/incomplete
- imported DPG rows can appear in Intake when they need cleanup/dedupe/matching
- staff can approve/reject intake, mark duplicate/invalid/archived, and separately set support and volunteer status
- staff can link a contact to a GEC voter or mark possible/no match
- possible GEC matches should show the actual candidate record before staff confirms it

### 3. GEC/public voter-list workspace

GEC data is public voter-file infrastructure, not Josh/Tina proprietary. DPG specifically discussed voter lists, address lookup, registered voters, and registered Democrat/member/supporter cross-reference.

Core requirement:

- import GEC voter list files
- preserve list date/version
- search GEC voters by name, address, village, precinct, and voter registration number when available
- search should be forgiving of punctuation, middle initials, and common name-format differences
- address search should normalize common PO Box/P.O. Box/HCR/HC and punctuation variants where possible
- show who should be at an address according to GEC
- link/create DPG contacts from GEC voters
- match DPG contacts to GEC voters
- show moved/village mismatch/possible match/no match states
- keep DPG-entered contact fields separate from official GEC voter fields so staff can see both what the person reported and what the current voter file says

This is a priority build item, not a distant optional feature.

### 4. DPG-owned data import

DPG discussed voter lists, registered Democrat lists, supporter/contact data, and a separate official membership roster.

Core requirement:

- explicit list type selection:
  - GEC voter list
  - DPG contacts/supporters
  - official DPG member roster
  - registered Democrat list
  - other/custom
- preview/mapping step if already available
- confirm import
- duplicate detection/review
- richer member-roster-vs-voter cross-reference, once DPG provides and defines the roster
- multiple list types: GEC voter list, registered Democrat list, DPG contacts/supporters, official DPG member roster

Current status:

- GEC import/search is implemented because we have real GEC files.
- Generic contact import is implemented.
- Official member roster, registered Democrat list, active party list, inactive party list, and custom list importers are intentionally pending until DPG provides actual files or sample schemas.
- The May 20 demo confirmed active/inactive DPG lists exist and have special retention rules; do not build destructive purge behavior into membership/list handling.

### 5. Village/precinct/address organization

DPG wants data organized by physical location, village, precinct, and possibly district.

Core requirement:

- Guam villages
- precinct references
- search/filter by village/precinct
- address/household lookup from GEC and DPG contact data
- conservative address normalization for common street suffix and locality variants

Do **not** inherit Josh/Tina district mapping.

Districts:

- leave empty/neutral unless DPG defines their own mapping
- add DPG-defined district grouping later if they want it

### 6. Roles and permissions

Stephanie specifically wanted GC/party members to input data but not delete/export everything, with access scoped to precinct/village/district and admins able to see all.

Core requirement:

- one internal DPG workspace first
- roles control access inside the workspace
- Administrator / Data Manager / Field Organizer / Village Coordinator / Canvasser
- no delete for non-admin users if already enforceable
- export restricted to appropriate roles if practical
- admin sees all
- precinct/village-scoped staff permissions
- DPG-defined district-scoped access

Current status:

- UI labels use DPG-facing role names.
- Internal database role values remain the original compatibility names.
- Export is limited to Administrator/Data Manager.
- Bulk contact import is limited to Administrator/Data Manager/Field Organizer.
- Contact-attempt correction is limited to Administrator/Data Manager.

### 7. Contact/canvassing history

DPG asked to know when a voter was contacted and how: in-person, phone, email, phone bank, etc.

Core requirement:

- structured contact attempts with date, method, outcome, user, notes, and follow-up
- methods: in-person, phone, SMS, email, phone bank, office visit, other
- outcomes: reached, not reached, left message, wrong number, refused, needs follow-up, completed
- canvassing route/household workflow
- Contact History is the actual interaction log. Follow-up fields are task-progress/outcome lanes for registration, voter-help, and volunteer requests; logging a first contact can start untouched lanes but does not resolve them.

### 8. Household/address lookup

DPG wants to pull up an address/household and see voters associated with that house.

Core requirement:

- household/address workspace
- address search across GEC voters and DPG contacts
- voters at address
- DPG contacts at address
- latest contact attempts per person
- support/registration needs per person
- create/link contacts from address results
- log canvass/contact updates from household results

### 9. SMS/email outreach

DPG asked about mass email, SMS reminders, and possibly autodialer integration.

Core requirement:

- SMS/email settings screens if stable
- opt-in fields respected
- live sending available only in approved DPG environments with configured sender credentials; dry-run/preview first for normal testing
- email/SMS templates: starter compose templates implemented for registration help, event/community updates, and volunteer follow-up
- live blast governance and recipient approval workflow: implemented through dry-run recipient preview plus required matching recipient-count confirmation for live sends
- outreach actions should create contact history records: implemented for SMS/email blast attempts
- reminder flows
- per-recipient SMS status visibility and resend-to-failed/undelivered recipients
- possible autodialer integration

### 10. QR signup / frictionless signup

DPG discussed QR signup/canvassing links.

Starter/foundation:

- public signup link works
- QR generation and signup-link attribution are implemented for general signup plus village/canvasser/outreach/custom source links
- inactive links are ignored for future attribution so stale links fall back to normal public signup
- QR-code download is implemented so DPG can reuse codes in flyers, group chats, and outreach materials
- unused links should be deletable; used links should be archived/deactivated to preserve attribution history

Core build:

- additional print-ready QR templates after DPG tests the workflow
- additional village/precinct/event attribution labels if DPG wants them

### 11. Poll watcher / election-day operations

DPG explicitly discussed poll watchers, Election Day voted/not-voted tracking, and war-room style reporting.

Starter/foundation:

- do **not** ship Josh/Tina's implementation
- keep out of starter UI unless it is clearly generic and stable

Core build:

- design with DPG from scratch
- DPG-owned poll watcher workflow
- precinct-scoped poll watcher access
- voted/not-voted tracking
- turnout/call-list dashboard
- Mike Weekly should be included in scoping/training before the August 1 primary

### 12. DPG quota/period tracking

The May 20 demo confirmed DPG needs a way to organize signup/contact credit by active quota or outreach periods. This is now DPG-requested and should be designed as DPG's own goals/period model, not copied from another campaign.

Core build:

- admin-defined periods with start/end dates
- one active/default period for new signups and contacts
- signup/contact attribution to the active period
- period filters for signup-link, user, village, and report counts
- duplicate cleanup rules so the same person is not double-counted where DPG expects unique-person counts

Current status:

- PR #41 merged the quota/period foundation to `main`: period management, active-period assignment for public/QR/staff signups, signup-link period counts with lifetime totals, dashboard active-period summary, period filters for Contacts/Intake/Reports/Signup Links, realtime cache invalidation, period drilldowns, and DB/model safeguards for one active period.
- Detailed goal rules, leaderboards, and unique-person quota credit should wait for DPG feedback.

Open questions:

- should quotas count raw signups, approved contacts, supporters, registered Democrats, volunteers, or multiple metrics?
- are goals party-wide, per village, per organizer, per signup link, or all of the above?
- what happens to pending Intake records when a period closes?

### 13. Maps/GIS/heatmaps

DPG asked about mapping voter locations, precinct maps, and possible heat maps.

Starter/foundation:

- defer

Core build:

- map voter locations by public/DPG data
- precinct/village visualizations
- heatmaps if useful

### 14. OCR/photo/ID scanning

DPG discussed paper/photo/OCR type possibilities indirectly through blue-sheet automation and later potential scan/import flows.

Starter/foundation:

- defer unless already generic and hidden behind admin/test flow

Core build:

- DPG-specific paper/OCR intake only if DPG defines the form/process
- avoid Josh/Tina blue-block-list assumptions

---

# Proper DPG build priorities

## Phase 1: DPG workflow reset

- one internal workspace
- visible Intake queue
- contacts visible immediately but not automatically supporters
- honest dashboard counts
- clean labels: contacts, intake, GEC voters, supporters, volunteers, outreach, and future official member-roster reporting
- remove/hide inherited queues that do not have a DPG workflow

Status: implemented. Membership is hidden from the active manual workflow and reserved for future official member-roster/list work.

## Phase 2: GEC voter list

- GEC voter-list import: implemented for DPG admins/data ops through the first-class GEC workspace.
- GEC voter search: implemented by name, address, village, precinct, and voter registration number.
- address/household view from GEC: implemented as address lookup showing GEC voters and DPG contacts at matching addresses.
- DPG contact to GEC match: implemented for creating contacts from GEC voters and linking existing contacts from the GEC workspace UI.
- DPG/GEC contact cross-reference reports: implemented for linked contacts, unlinked contacts, GEC voters not in DPG contacts, possible GEC matches, and DPG/GEC address/village/precinct mismatches. Official member-roster and registered-Democrat cross-reference still needs real DPG list samples.

## Phase 3: Contacts, households, outreach

- structured contact history: implemented for contact detail with channel, outcome, timestamp, note, and staff attribution.
- contact-attempt correction: implemented for Administrator/Data Manager with audit history.
- household/address workspace: implemented at `/admin/households`, backed by the current GEC household lookup, DPG contact address search, conservative address normalization, and household canvass logging.
- follow-up queues: implemented for registration, voter-help, and volunteer work, now with latest-contact summaries, queue-card logging into the shared contact history, and automatic untouched-lane start when a first contact attempt is logged.
- roles/scoped permissions: implemented for the current DPG-facing role model.

## Phase 4: Communications and list operations

- QR attribution: implemented.
- QR-code download: implemented.
- signup-link delete/archive lifecycle: implemented.
- SMS/email templates: implemented starter templates.
- recipient review: implemented through dry-run preview and count confirmation before live sends.
- SMS delivery status and resend-to-failed/undelivered: requested in the May 20 demo, pending provider-status integration.
- DPG quota/period tracking: requested in the May 20 demo; foundation merged in PR #41 with detailed goal/leaderboard rules pending DPG feedback.
- exports/import reports: DPG/GEC contact cross-reference reports are implemented; explicit non-GEC list types and official member-roster/registered-Democrat list-lineage reporting remain pending actual DPG list samples.

## Phase 5: Election operations

- poll watcher
- voted/not-voted tracking
- war-room dashboard
- maps/heatmaps
