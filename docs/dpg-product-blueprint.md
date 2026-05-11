# DPG Product Blueprint

**Last updated:** May 11, 2026  
**Purpose:** Source-of-truth plan for turning the current DPG fork into the Democratic Party of Guam voter engagement and election operations platform.

## Product goal

Build a DPG-owned platform for:

- importing and searching the public GEC voter list
- managing DPG contacts, members, supporters, volunteers, and prospects
- matching DPG records against public voter-file data
- organizing outreach by address, household, village, precinct, and eventually district
- tracking every contact attempt across SMS, email, phone, phone bank, and in-person visits
- coordinating registration help, absentee/homebound/ride help, volunteer follow-up, and later Election Day operations

This should not be a patched copy of a campaign tracker. It should reuse Shimizu Technology's generic platform infrastructure, but DPG workflows should be designed around DPG's own needs.

## Core product principles

1. **GEC voter data is core public infrastructure.** It is not Josh/Tina proprietary. DPG needs import, search, address lookup, and matching against the GEC list.
2. **If a status exists, there must be a DPG workflow for it.** Hidden inherited queues create broken experiences.
3. **Public signups must be visible immediately, but should not inflate official supporter/member counts.**
4. **Use one internal workspace first.** Admin/Data Ops split is likely inherited complexity. Roles should control permissions inside one DPG workspace.
5. **Contact history is central.** DPG needs to know who contacted a person, when, by what method, what happened, and what should happen next.
6. **Election Day tools come later.** Poll watcher, voted/not-voted tracking, and war-room dashboards should be designed with DPG instead of copied from another campaign's operating model.

## Core records and concepts

### GEC Voter

Official/public voter-file record imported from the Guam Election Commission list.

Needs:

- import GEC list files
- preserve list version/date
- search by name, address, village, precinct, and voter registration number when available
- display household/address groupings from voter-file data
- identify moved/village-mismatch records across list versions
- support matching DPG contacts to official voter records

### DPG Contact

Any person DPG knows about.

Sources:

- public signup
- QR signup
- staff manual entry
- imported DPG member/supporter list
- imported registered Democrat list
- canvassing/contact from a GEC voter record

This should be the default visible record type. A contact is not automatically an official supporter or member.

### Intake

Records that need DPG classification or cleanup.

Examples:

- public signup awaiting review/classification
- staff-entered contact needing cleanup
- imported row needing dedupe or voter-file match
- possible duplicate
- possible GEC match
- no GEC match

Intake must have a visible DPG screen. It should not be a hidden inherited public-review/supporter-review queue.

### Relationship / Classification

A DPG contact can be classified independently from their voter-file status.

Possible relationship statuses:

- new intake
- active contact
- supporter
- member
- volunteer
- undecided/unknown
- not supporting
- duplicate
- invalid/spam
- archived

This is different from GEC match status.

### GEC Match Status

Tracks whether a DPG contact maps to an official public voter-file record.

Possible statuses:

- not checked
- matched GEC voter
- possible match
- multiple possible matches
- no match
- address/village mismatch
- moved/transfer suspected

### Household / Address

DPG needs to search an address and see people associated with that location.

Household/address workspace should show:

- GEC voters at that address
- DPG contacts linked to that address
- household members submitted together
- latest contact attempts for each person
- support/registration needs
- relationship/classification

### Contact Attempt

Every interaction with a person should be recorded.

Fields:

- contact/contacted person
- staff user
- method: in-person, phone call, SMS, email, phone bank, office visit, other
- outcome: reached, not reached, left message, wrong number, refused, needs follow-up, completed
- date/time
- notes
- next follow-up date/status when needed

This supports the workflow where staff can see that Leon sent SMS, Kami emailed, and Stassie visited in person.

### Outreach Need

DPG needs work queues for:

- voter registration help
- absentee ballot help
- homebound voting help
- ride to polls
- volunteer follow-up
- membership follow-up
- donation interest/follow-up if DPG wants it

## Recommended internal workspace

Use one DPG internal workspace instead of separate Admin/Data Ops areas.

Suggested navigation:

- Dashboard
- Contacts
- Intake
- GEC Voter List
- Households / Address Search
- Outreach
- Imports
- Reports
- Users
- Settings

Role permissions should control access inside that workspace.

Suggested roles:

- Main Admin
- Data Manager
- Staff
- Field Organizer
- Canvasser
- Poll Watcher later

## Workflow design

### Public signup workflow

1. Person submits public/QR signup.
2. System creates visible DPG Contact.
3. Contact appears in Intake as new public signup.
4. Contact does **not** count as official supporter/member until classified.
5. Staff can match to GEC voter, dedupe, classify, and assign follow-up.

Current Phase 1 implementation note: public signups, staff entries, and contact imports create visible DPG contacts with `new_intake` classification by default. They appear in Contacts and Intake immediately, but they do not count as official supporters/members until DPG classifies them.

### Staff/manual entry workflow

1. Staff creates a visible DPG Contact.
2. Contact can optionally go to Intake if unclassified or incomplete.
3. Staff can match to GEC voter immediately if search is available.
4. Contact history begins from the entry/contact event.

### GEC/address canvassing workflow

1. Staff searches an address, village, precinct, or voter name in GEC Voter List.
2. System shows who should be at that address according to GEC.
3. Staff opens a person and records contact attempt.
4. Staff can create/link a DPG Contact from that GEC voter.
5. Staff marks relationship/classification and follow-up needs.
6. Future staff can see all prior attempts by person and household.

### Import workflow

1. User chooses list type:
   - GEC voter list
   - DPG contacts/supporters
   - DPG members
   - registered Democrat list
   - other custom list
2. Upload file.
3. Preview/mapping.
4. Confirm import.
5. System dedupes/matches where possible.
6. Imported records go to the appropriate workspace:
   - GEC records into GEC Voter List
   - DPG records into Contacts/Intake

## Priority plan

### Phase 0: Documented workflow reset

- Use this blueprint as the source of truth.
- Audit inherited states/scopes/routes:
  - public review
  - supporter review
  - official supporter
  - working supporter
  - Data Ops vs Admin split
  - Josh/Tina-specific leftover model fields
- Decide what to keep, rename, remove, or replace.

### Phase 1: DPG Foundation Reset

- Replace hidden public-review/supporter-review assumptions with visible DPG Intake. **Implemented May 11, 2026.**
- Change dashboard counts to: **Implemented May 11, 2026.**
  - total contacts
  - new intake
  - matched GEC voters
  - supporters
  - members
  - needs follow-up
- Simplify to one internal DPG workspace. **Implemented May 11, 2026; legacy `/data` and `/team` routes redirect into `/admin`.**
- Rename UI copy away from inherited campaign language where confusing. **Implemented across the main workspace surfaces; inactive legacy components still exist in source for redirect/backward compatibility.**
- Ensure public signup, manual entry, imports, search, reports, users, audit logs, and outreach basics are coherent in the new model. **Implemented and covered by the Rails test suite plus frontend lint/build.**

### Phase 2: GEC Voter List Workspace

- Restore/build GEC voter-list import flow from reusable campaign-tracker foundation. **Implemented in the Phase 2 GEC workspace as a DPG-scoped spreadsheet import/preview using the reusable `GecImportService`.**
- Add GEC list version/date management. **Implemented for imported list dates and recent import history; full import artifact/change review remains a later hardening pass.**
- Add GEC voter search by name, address, village, precinct. **Implemented at `/admin/gec-voters` and `/api/v1/gec_voters`.**
- Add address/household grouping from GEC data. **Implemented as address lookup that shows GEC voters and existing DPG contacts at matching addresses.**
- Add DPG contact to GEC voter matching. **Implemented for creating a DPG contact from a GEC voter and linking the resulting contact to the voter record. Existing-contact linking exists in the API; a richer UI picker is deferred to the contact-detail pass.**
- Add skipped-row/import-error review if needed.

### Phase 3: Contact/Household/Outreach Operations

- Build DPG Contact detail around:
  - classification
  - GEC match
  - household/address
  - contact history
  - support needs
- Build Contact Attempt logging.
- Build Household/Address workspace.
- Build Outreach queues for registration, absentee, homebound, ride, volunteer, membership follow-up.

### Phase 4: Imports and List Types

- Support list-type-specific imports:
  - GEC voter list
  - DPG contacts/supporters
  - DPG members
  - registered Democrat list
- Track source/list type on records.
- Add cross-reference reports:
  - DPG contacts not matched to GEC
  - GEC voters marked supporter/member
  - members needing registration help
  - address/village mismatch

### Phase 5: Communications

- SMS/email templates.
- Recipient review before blasts.
- Opt-in/legal language and suppression handling.
- Contact attempts generated from outreach actions.
- Autodialer export/integration if DPG chooses a provider.

### Phase 6: Election Operations

- DPG-designed poll watcher workflow.
- Poll watcher roles and assigned precinct access.
- Voted/not-voted tracking.
- Election Day turnout/call-list dashboard.
- War-room reporting.
- Maps/heatmaps where useful.

## Immediate next implementation recommendation

Start with Phase 1, then Phase 2.

The minimum proper DPG reset before broader tester use is:

1. One internal workspace decision.
2. Visible Intake queue.
3. Honest dashboard counts.
4. Contacts show immediately but are not automatically supporters/members.
5. GEC voter-list import/search is restored as a first-class workspace.
6. Contact history data model and first UI entry point.
