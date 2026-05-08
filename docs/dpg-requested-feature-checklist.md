# DPG Requested Feature Checklist

**Purpose:** Ensure Monday's DPG build is not just a shell. It should include a useful, basic version of what DPG asked for, while leaving heavier/ambiguous workflows for follow-up.

**Sources reviewed:**

- `Democratic-Party/1) - In Person meeting with Auntie Stephanie and Ethan - April 27, 2026.md`
- `Democratic-Party/2) - Democratic Pary Meeting with Mrs. Stephanie and her team - April 2nd, 2026.md`

## What DPG clearly asked for

### 1. Voter/supporter CRM

DPG asked for a voter information / CRM-style system where data can be uploaded, sorted, searched, and managed.

Monday version should include:

- supporter/contact list
- supporter/contact detail page
- create/edit supporter/contact
- basic search/filter
- notes or contact/follow-up fields if already present
- export basics

### 2. DPG-owned data import

DPG discussed voter lists, registered Democrat lists, and a separate supporter/membership roster.

Monday version should include:

- CSV/Excel import for DPG-owned supporter/member lists
- preview/mapping step if already available
- confirm import
- duplicate detection/review

Next phase:

- richer membership-vs-voter cross-reference
- multiple list types: GEC voter list, registered Democrat list, DPG support/membership roster

### 3. GEC/public voter-list foundation

GEC data is public/public-ish voter infrastructure, not Josh/Tina proprietary. DPG specifically discussed GEC voter lists and registered Democrat voter lists.

Monday version should include if stable:

- ability to keep/import/search public voter-list records, or at minimum preserve this foundation
- avoid Josh/Tina-specific vetting/quota statuses

Next phase:

- cross-reference DPG membership/supporter list against GEC voter file
- identify registered Democrats vs DPG roster records
- identify roster people who may not be registered voters

### 4. Village/precinct organization

DPG wants data organized by physical location, village, precinct, and possibly district.

Monday version should include:

- Guam villages
- precinct references if available/stable
- search/filter by village/precinct where possible

Do **not** inherit Josh/Tina district mapping.

Districts:

- leave empty/neutral unless DPG defines their own mapping
- add DPG-defined district grouping later if they want it

### 5. Roles and permissions

Stephanie specifically wanted GC/party members to input data but not delete/export everything, with access scoped to precinct/village/district and admins able to see all.

Monday version should include:

- admin/staff roles
- user management
- no delete for non-admin users if already enforceable
- export restricted to appropriate roles if practical
- admin sees all

Next phase:

- precinct/village-scoped staff permissions
- DPG-defined district-scoped access

### 6. Contact/canvassing history

DPG asked to know when a voter was contacted and how: in-person, phone, email, phone bank, etc.

Monday version should include basic version:

- contact/follow-up status
- notes field or contact log if already available
- basic outreach status queue

Next phase:

- structured contact attempts with date/method/outcome
- canvassing route/household workflow

### 7. Household/address lookup

DPG wants to pull up an address/household and see voters associated with that house.

Monday version:

- not required unless already stable
- keep address fields and search if already present

Next phase:

- household view
- address search
- voters at address

### 8. SMS/email outreach

DPG asked about mass email, SMS reminders, and possibly autodialer integration.

Monday version should include:

- SMS/email settings screens if stable
- opt-in fields respected
- no live blast unless Leon/DPG explicitly approves

Next phase:

- DPG sender setup
- email/SMS templates
- reminder flows
- possible autodialer integration

### 9. QR signup / frictionless signup

DPG discussed QR signup/canvassing links.

Monday version:

- public signup link must work
- QR generation is useful if generic and stable, but not required for first smoke test

Next phase:

- DPG-branded QR downloads/share links
- village/precinct attribution if DPG wants it

### 10. Poll watcher / election-day operations

DPG explicitly discussed poll watchers, Election Day voted/not-voted tracking, and war-room style reporting.

Monday version:

- do **not** ship Josh/Tina's implementation
- keep out of starter UI unless it is clearly generic and stable

Next phase:

- design with DPG from scratch
- DPG-owned poll watcher workflow
- precinct-scoped poll watcher access
- voted/not-voted tracking
- turnout/call-list dashboard

### 11. Maps/GIS/heatmaps

DPG asked about mapping voter locations, precinct maps, and possible heat maps.

Monday version:

- defer

Next phase:

- map voter locations by public/DPG data
- precinct/village visualizations
- heatmaps if useful

### 12. OCR/photo/ID scanning

DPG discussed paper/photo/OCR type possibilities indirectly through blue-sheet automation and later potential scan/import flows.

Monday version:

- defer unless already generic and hidden behind admin/test flow

Next phase:

- DPG-specific paper/OCR intake only if DPG defines the form/process
- avoid Josh/Tina blue-block-list assumptions

---

# Monday minimum viable DPG build

This is the minimum that feels like a real useful app, not a shell:

## Must work

- DPG branding across public/admin surfaces
- public signup creates a DPG supporter/contact
- admin/staff login works
- supporter/contact list loads
- supporter/contact detail loads
- staff can create/edit a contact manually
- CSV/Excel import can bring in DPG-owned list records
- duplicate review works or at least duplicate warnings work
- village/precinct fields/search/filter work where available
- basic reports/export works
- users/roles page works
- audit logs work if already present

## Should work if stable

- GEC voter-list import/search foundation
- outreach/follow-up queue
- SMS/email settings visibility
- QR signup link generation

## Explicitly okay to defer

- DPG membership-vs-GEC cross-reference automation
- household/address voter grouping
- structured canvassing history
- live SMS/email blasts
- poll watcher/election-day command center
- war-room dashboard
- GIS/heatmaps
- OCR/photo/ID scan
- DPG-defined district mapping

---

# Product stance for Monday

We should be honest in the handoff:

> This is the first DPG testing build. It includes the core signup, CRM, import, search, roles, and reporting foundation. The heavier Election Day, map, OCR, and advanced cross-reference workflows are next-phase items that we will shape around DPG's process.

This avoids overpromising while still delivering something real.
