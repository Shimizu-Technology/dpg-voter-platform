# DPG Product Blueprint

**Last updated:** May 16, 2026  
**Purpose:** Source-of-truth plan for turning the current DPG fork into the Democratic Party of Guam voter engagement and election operations platform.

## Product goal

Build a DPG-owned platform for:

- importing and searching the public GEC voter list
- managing DPG contacts, supporters, volunteers, prospects, and future official member-roster cross-references
- matching DPG records against public voter-file data
- organizing outreach by address, household, village, precinct, and eventually district
- tracking every contact attempt across SMS, email, phone, phone bank, and in-person visits
- coordinating registration help, absentee/homebound/ride help, volunteer follow-up, and later Election Day operations

This should not be a patched copy of a campaign tracker. It should reuse Shimizu Technology's generic platform infrastructure, but DPG workflows should be designed around DPG's own needs.

## Current implementation checkpoint

As of May 12, 2026, the DPG platform is deployed online and the first core build phases are merged to `main`:

- Phase 1: DPG foundation reset and unified `/admin` workspace.
- Phase 2: GEC voter-list workspace.
- Phase 3: contact history and household/address workspace.
- Outreach queue logging enhancement: latest contact attempt display and inline attempt logging from the Follow-Up Queue.
- Communications governance: SMS/email dry-run recipient review, starter templates, and blast contact-attempt logging.

The code has been reviewed and covered by focused backend/frontend checks, but the admin side still needs a full deployed browser QA pass before we should treat it as production-validated for DPG staff.

## Core product principles

1. **GEC voter data is core public infrastructure.** It is not Josh/Tina proprietary. DPG needs import, search, address lookup, and matching against the GEC list.
2. **If a status exists, there must be a DPG workflow for it.** Hidden inherited queues create broken experiences.
3. **Public signups must be visible immediately, but should not inflate supporter counts until reviewed.**
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
- imported DPG contact/supporter list
- future imported official DPG member roster
- imported registered Democrat list
- canvassing/contact from a GEC voter record

This should be the default visible record type. A contact is not automatically a supporter.

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

The active staff workflow should stay focused on the distinctions DPG can act on now:

- record lifecycle: new intake, active contact, duplicate, invalid/spam, archived
- support status: not reviewed, supporter, undecided, not supporting
- volunteer interest: not reviewed, interested, active volunteer, not interested
- contacted status: derived from contact-attempt history, including who contacted the person, when, how, outcome, notes, and follow-up

This is different from GEC match status.

DPG did discuss member lists/party membership rosters in the meetings, so the app still keeps the legacy `membership_status` field in the database/model for compatibility and future work. Membership should stay hidden from the manual UI until DPG defines an official member-roster import or cross-reference workflow. When it returns, it should be treated as a roster/list signal, not as a second staff dropdown that duplicates support status.

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
- official member-roster follow-up, once DPG defines that workflow
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

- Administrator
- Data Manager
- Field Organizer
- Village Coordinator
- Canvasser
- Poll Watcher later

Implementation note: the database role values still use the original internal names for compatibility (`campaign_admin`, `data_team`, `district_coordinator`, `village_chief`, `block_leader`), while the UI presents the DPG labels above. Export is intentionally limited to Administrator/Data Manager, bulk contact import to Administrator/Data Manager/Field Organizer, and canvassing/contact logging remains available to scoped field users.

## Workflow design

### Public signup workflow

1. Person submits public/QR signup.
2. System creates visible DPG Contact.
3. Contact appears in Intake as new public signup.
4. Contact does **not** count as a supporter until reviewed/classified.
5. Staff can match to GEC voter, dedupe, classify, and assign follow-up.

Current Phase 1 implementation note: public signups, staff entries, and contact imports create visible DPG contacts with `new_intake` classification by default. They appear in Contacts and Intake immediately, but they do not count as supporters until DPG classifies them. The legacy `membership_status` field remains in the backend for future official member-roster work, but it is intentionally hidden from the active manual workflow.

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
   - official DPG member roster
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
  - future official member-roster matches
  - needs follow-up
- Simplify to one internal DPG workspace. **Implemented May 11, 2026; legacy `/data` and `/team` routes redirect into `/admin`.**
- Rename UI copy away from inherited campaign language where confusing. **Implemented across the main workspace surfaces; inactive legacy components still exist in source for redirect/backward compatibility.**
- Ensure public signup, manual entry, imports, search, reports, users, audit logs, and outreach basics are coherent in the new model. **Implemented and covered by the Rails test suite plus frontend lint/build.**

### Phase 2: GEC Voter List Workspace

- Restore/build GEC voter-list import flow from reusable campaign-tracker foundation. **Implemented in the Phase 2 GEC workspace as a DPG-scoped spreadsheet import/preview using the reusable `GecImportService`.**
- Add GEC list version/date management. **Implemented for imported list dates and recent import history; full import artifact/change review remains a later hardening pass.**
- Add GEC search, address lookup, create-contact, and link-existing-contact workflows. **Implemented in `/admin/gec-voters`; the link-existing-contact UI is available inline from voter search results.**
- Add first-pass household/address operations. **Implemented in Phase 3 through `/admin/households`, which combines GEC voters and DPG contacts by searched address.**
- Add structured contact history. **Implemented in Phase 3 on contact detail through logged call, SMS, and in-person attempts with outcomes and notes.**
- Add GEC voter search by name, address, village, precinct. **Implemented at `/admin/gec-voters` and `/api/v1/gec_voters`.**
- Add address/household grouping from GEC data. **Implemented as address lookup that shows GEC voters and existing DPG contacts at matching addresses.**
- Add DPG contact to GEC voter matching. **Implemented for creating a DPG contact from a GEC voter and linking existing DPG contacts from the GEC workspace UI.**
- Add skipped-row/import-error review if needed.
- Post-PR #31 hardening target: compare the DPG importer against the campaign-tracker importer for large-PDF progress visibility, recoverability from interrupted jobs, skipped-row/source-artifact review, import-diff review, and re-vetting visibility. Keep only generic public-GEC infrastructure; do not import Josh/Tina-specific operating assumptions.

### Phase 3: Contact/Household/Outreach Operations

- Build DPG Contact detail around:
  - classification **Implemented.**
  - GEC match **Implemented.**
  - household/address **Implemented through household lookup and GEC/contact linking.**
  - contact history **Implemented for call, SMS, email blast, and in-person attempts.**
  - support needs **Not fully implemented; should be designed with DPG labels and workflows.**
- Build Contact Attempt logging. **Implemented on contact detail, Follow-Up Queue cards, and SMS/email blast jobs.**
- Build Household/Address workspace. **Implemented as `/admin/households`.**
- Build Outreach queues for registration, absentee, homebound, ride, volunteer, and future official member-roster follow-up if DPG defines it. **Partially implemented through the Follow-Up Queue, classification filters, latest-attempt summaries, and inline attempt logging; richer DPG-specific queue labels and support-need workflows remain.**
- Surface latest contact attempts in the Follow-Up Queue and let staff log call/SMS/in-person touches from each queue card. **Implemented in the outreach queue so queue work updates the shared contact-history timeline.**

### Phase 4: Imports and List Types

- Support list-type-specific imports:
  - GEC voter list **Implemented.**
  - DPG contacts/supporters **Partially implemented through the existing contact import flow; explicit list type selection still needed.**
  - official DPG member rosters **Not implemented as a first-class list type yet; membership remains reserved until DPG defines this roster workflow.**
  - registered Democrat list **Not implemented as a first-class list type yet.**
- Track source/list type on records. **Partially implemented through existing source/origin fields; needs explicit DPG list-type modeling.**
- Add cross-reference reports:
  - DPG contacts not matched to GEC
  - GEC voters marked as supporters
  - official member-roster records needing registration help, once that list type exists
  - address/village mismatch
  - **Not fully implemented yet; this is the next core product phase.**

### Phase 5: Communications

- SMS/email templates. **Implemented as starter templates on the SMS and Email Center compose screens.**
- Recipient review before blasts. **Implemented for live SMS/email blasts: staff must run dry-run preview and confirm the matching recipient count before queueing a send.**
- Opt-in/legal language and suppression handling. **Needs operational review/hardening before broad live sends.**
- Contact attempts generated from outreach actions. **Implemented for SMS/email blast jobs so attempted sends appear in the contact-history timeline.**
- Autodialer export/integration if DPG chooses a provider. **Deferred.**

### Phase 6: Election Operations

- DPG-designed poll watcher workflow.
- Poll watcher roles and assigned precinct access.
- Voted/not-voted tracking.
- Election Day turnout/call-list dashboard.
- War-room reporting.
- Maps/heatmaps where useful.

## Immediate next implementation recommendation

The next step should be operational confidence before more feature expansion.

Recommended order:

1. Run a full deployed admin QA pass using the live site:
   - public signup to Intake/Contacts
   - manual entry/import
   - GEC import/search/link/create-contact
   - household lookup
   - contact detail logging
   - Follow-Up Queue logging
   - SMS/email dry runs
   - reports, users, audit log
   - mobile/tablet layouts
2. Create Auntie Stephanie as the main admin once she gives the preferred email.
3. Hand off to a small DPG tester group for familiarization and workflow feedback.
4. Build Phase 4 explicit list types and cross-reference reports:
   - DPG contacts/supporters
   - official DPG member rosters
   - registered Democrat list
   - GEC matched/unmatched reports
   - supporter and future member-roster registration status reports
5. Polish DPG role labels and permission descriptions.
6. Polish QR signup attribution based on DPG testing; the first QR/share-link attribution slice is implemented on PR #35.
7. Scope richer support-need queues and election-day operations with DPG after they have used the deployed foundation.
