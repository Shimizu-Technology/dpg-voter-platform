# DPG Requested Feature Checklist

**Purpose:** Track what DPG requested and convert it into the proper DPG platform plan. The current app should be treated as a starter foundation; the next work should follow `docs/dpg-product-blueprint.md`.

**Sources reviewed:**

- `Democratic-Party/1) - In Person meeting with Auntie Stephanie and Ethan - April 27, 2026.md`
- `Democratic-Party/2) - Democratic Pary Meeting with Mrs. Stephanie and her team - April 2nd, 2026.md`

## What DPG clearly asked for

### 1. DPG contacts / voter engagement CRM

DPG asked for a voter information / CRM-style system where data can be uploaded, sorted, searched, and managed.

Core requirement:

- contact list
- contact detail page
- create/edit contact
- basic search/filter
- relationship/classification: supporter, member, volunteer, undecided, not supporting, invalid/duplicate
- contact/follow-up history
- export basics

Important distinction:

- A DPG contact is not automatically an official supporter or member.
- Public signups and staff entries should be visible immediately, but should go through Intake/classification before they inflate supporter/member counts.

### 2. DPG Intake queue

DPG needs a simple visible review/classification workspace. This is not the inherited Josh/Tina public-review/supporter-review flow.

Core requirement:

- public signups appear in Intake
- staff/manual entries can appear in Intake when unclassified/incomplete
- imported DPG rows can appear in Intake when they need cleanup/dedupe/matching
- staff can classify records as supporter, member, volunteer, undecided, not supporting, duplicate, invalid, archived
- staff can link a contact to a GEC voter or mark possible/no match

### 3. GEC/public voter-list workspace

GEC data is public voter-file infrastructure, not Josh/Tina proprietary. DPG specifically discussed voter lists, address lookup, registered voters, and registered Democrat/member/supporter cross-reference.

Core requirement:

- import GEC voter list files
- preserve list date/version
- search GEC voters by name, address, village, precinct, and voter registration number when available
- show who should be at an address according to GEC
- link/create DPG contacts from GEC voters
- match DPG contacts to GEC voters
- show moved/village mismatch/possible match/no match states

This is a priority build item, not a distant optional feature.

### 4. DPG-owned data import

DPG discussed voter lists, registered Democrat lists, and a separate supporter/membership roster.

Core requirement:

- explicit list type selection:
  - GEC voter list
  - DPG contacts/supporters
  - DPG members
  - registered Democrat list
  - other/custom
- preview/mapping step if already available
- confirm import
- duplicate detection/review
- richer membership-vs-voter cross-reference
- multiple list types: GEC voter list, registered Democrat list, DPG support/membership roster

### 5. Village/precinct/address organization

DPG wants data organized by physical location, village, precinct, and possibly district.

Core requirement:

- Guam villages
- precinct references
- search/filter by village/precinct
- address/household lookup from GEC and DPG contact data

Do **not** inherit Josh/Tina district mapping.

Districts:

- leave empty/neutral unless DPG defines their own mapping
- add DPG-defined district grouping later if they want it

### 6. Roles and permissions

Stephanie specifically wanted GC/party members to input data but not delete/export everything, with access scoped to precinct/village/district and admins able to see all.

Core requirement:

- one internal DPG workspace first
- roles control access inside the workspace
- main admin / data manager / staff / field organizer / canvasser
- no delete for non-admin users if already enforceable
- export restricted to appropriate roles if practical
- admin sees all
- precinct/village-scoped staff permissions
- DPG-defined district-scoped access

### 7. Contact/canvassing history

DPG asked to know when a voter was contacted and how: in-person, phone, email, phone bank, etc.

Core requirement:

- structured contact attempts with date, method, outcome, user, notes, and follow-up
- methods: in-person, phone, SMS, email, phone bank, office visit, other
- outcomes: reached, not reached, left message, wrong number, refused, needs follow-up, completed
- canvassing route/household workflow

### 8. Household/address lookup

DPG wants to pull up an address/household and see voters associated with that house.

Core requirement:

- household/address workspace
- address search across GEC voters and DPG contacts
- voters at address
- DPG contacts at address
- latest contact attempts per person
- support/registration needs per person

### 9. SMS/email outreach

DPG asked about mass email, SMS reminders, and possibly autodialer integration.

Core requirement:

- SMS/email settings screens if stable
- opt-in fields respected
- live sending available only in approved DPG environments with configured sender credentials; dry-run/preview first for normal testing
- email/SMS templates
- live blast governance and recipient approval workflow
- outreach actions should create contact history records
- reminder flows
- possible autodialer integration

### 10. QR signup / frictionless signup

DPG discussed QR signup/canvassing links.

Starter/foundation:

- public signup link must work
- QR generation is useful if generic and stable, but not required for first smoke test

Core build:

- DPG-branded QR downloads/share links
- village/precinct attribution if DPG wants it

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

### 12. Maps/GIS/heatmaps

DPG asked about mapping voter locations, precinct maps, and possible heat maps.

Starter/foundation:

- defer

Core build:

- map voter locations by public/DPG data
- precinct/village visualizations
- heatmaps if useful

### 13. OCR/photo/ID scanning

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
- contacts visible immediately but not automatically official supporters/members
- honest dashboard counts
- clean labels: contacts, intake, GEC voters, supporters, members, outreach
- remove/hide inherited queues that do not have a DPG workflow

## Phase 2: GEC voter list

- GEC voter-list import
- GEC voter search
- address/household view from GEC
- DPG contact to GEC match
- DPG list cross-reference

## Phase 3: Contacts, households, outreach

- structured contact history
- household/address workspace
- follow-up queues
- roles/scoped permissions

## Phase 4: Communications and list operations

- QR attribution
- SMS/email templates
- recipient review
- exports/import reports

## Phase 5: Election operations

- poll watcher
- voted/not-voted tracking
- war-room dashboard
- maps/heatmaps
