# Becky Implementation Plan

**Status:** Core Becky intake + follow-up work largely implemented; election-day full-voter workflow in rollout hardening
**Date:** 2026-04-20
**Owner:** Campaign Tracker team

## Purpose

This document captures the agreed implementation direction for the Becky follow-up work after the Frank branding phase.

It exists to answer one simple question:

- what exactly are we building for Becky next?

This is the planning source of truth for the next supporter-intake and operations follow-up work.

## High-Level Summary

The Becky work should focus on:

1. expanding the public supporter signup to collect operationally useful follow-up data
2. supporting structured household capture
3. making those new intake fields visible to staff in review/detail/reporting flows
4. supporting follow-up workflows for registration and related help requests
5. documenting the poll watcher requirement clearly so it is not lost or conflated with supporter-only turnout logic

## Confirmed Product Direction

## 1. Public signup intake expansion

The public supporter signup should capture the things Becky needs for real campaign operations, not just basic supporter information.

### Required public form updates

- replace the current registered-voter checkbox with a 3-state choice:
  - `Yes`
  - `No`
  - `Not sure`
- add a conditional follow-up field:
  - `If yes, where do you vote if different from where you live?`
- add structured campaign-help request checkboxes:
  - `Get involved in the campaign`
  - `Absentee ballot help`
  - `Homebound voting help`
  - `Register to vote help`
  - `Ride to the polls`
- allow an optional `Who referred you?` fallback text field only when no referral code / leader link is already present

### Why

These fields create direct operational value:

- they tell the campaign who needs follow-up
- they separate uncertain or unregistered voters from already-registered supporters
- they support registrar, outreach, and election-support workflows

## 2. Household capture should be structured, not free text

Becky’s household ask is valid, but it should not be implemented as a large free-text field.

### Do not implement

- a free-text `Additional household supporters` box
- a notes-style field where staff must parse names manually later

### Do implement

- an optional structured repeatable household-member flow in the public signup
- one shared household block for:
  - street address
  - village
  - primary household phone
  - primary household email
- separate per-person supporter rows for:
  - first name
  - middle name optional
  - last name
  - DOB / birth year
  - registered voter status
  - any person-level follow-up fields we decide belong there

### Expected system behavior

- each household member becomes a separate supporter record
- all records stay linked through a household grouping model
- supporter detail should show related household members
- campaign staff should be able to recognize that multiple supporters belong to one household
- outreach should avoid treating one household like several unrelated people when that matters operationally

## 3. Staff visibility is required, not optional

Any new public intake field must be visible and usable by staff after submission.

### Required staff surfaces

The new Becky intake fields should appear clearly in:

- `Public Signup Review`
- `Supporter Review Queue`
- `Supporter Detail`
- reports / filters where operationally useful

### Minimum staff-visible data

- registered voter status
- alternate voting-location note
- campaign-help request flags
- referral fallback text if provided
- household membership / related household supporters

## 4. Follow-up workflow needs to be operationally useful

The Becky work is not just about storing more fields. It is about helping the campaign act on them.

### Expected outcomes

Staff should be able to identify:

- supporters who answered `No`
- supporters who answered `Not sure`
- supporters with `No GEC Match`
- supporters who need registration help
- supporters who need absentee / homebound / ride-to-polls help
- supporters who need general campaign follow-up

### Direction

This does not necessarily require a brand new complex workflow immediately, but the implementation must support:

- filtering
- reporting
- village-based follow-up
- easy handoff to the appropriate operational lead

### Follow-up owner model

The workflow should be designed so that it can be used by:

- Becky directly
- a registrar lead
- another limited operational role later

## 5. Poll watcher requirement must be documented separately and clearly

Becky made an important clarification:

- poll watchers do **not** only work from the campaign’s supporter list
- they need to work from the full registered voter list for the precinct / polling context
- the campaign supporter list is then overlaid on top of that to determine which supporters still need GOTV follow-up

### Core poll watcher rule

Poll watchers should be able to mark turnout against the full GEC voter universe relevant to their assigned area.

The app should then derive:

- which registered voters have voted
- which of those voters are campaign supporters
- which campaign supporters have **not** voted yet and therefore should be called or followed up

### Important distinction

Poll watcher turnout tracking is:

- based on the full GEC list
- not based only on campaign supporters

Campaign outreach logic is:

- based on the intersection of:
  - the campaign supporter list
  - and the set of voters who have not yet voted

### Why this matters

If the app only shows supporters to poll watchers, it skips the real election-day working list Becky described.

The campaign needs:

- complete turnout marking against the full voter roll
- then a supporter overlay to drive the “who still needs a call?” list

### Scope note

This is a real product requirement, but it is a separate election-day workflow track.

It should be documented now and implemented intentionally later, not folded sloppily into the public-intake branch.

## What This Becky Phase Should Include

### Include now

- public signup intake expansion
- structured household capture
- staff visibility for new intake fields
- data/report/filter support for Becky follow-up use cases

### Do not include now

- free-text household capture
- full poll watcher / election-day workflow expansion
- broad war room redesign
- unrelated public branding work

## Current Implementation Status

### What is now shipped

- public signup intake expansion:
  - 3-state self-reported voter status
  - votes-elsewhere note
  - structured support-request checkboxes
  - referred-by fallback text
- structured household capture:
  - linked household records
  - household member creation from public signup
  - household visibility on supporter detail
- staff visibility:
  - public signup review
  - supporter review queue
  - supporter detail
  - supporters list
  - dedicated follow-up queue
  - supporter-based report preview and export support
- follow-up distinction improvements:
  - clear separation between `GEC Found` and `Registered via follow-up`
  - reporting/filter visibility for Becky supporter workflows
  - split registration follow-up vs support-help follow-up statuses and filters
  - outreach queue prioritization for unresolved registration/support work
- staff entry parity:
  - Becky intake fields available in manual staff entry
  - intake/reporting parity across public signup, admin review, detail, and exports
- role/access improvements related to Becky operational work:
  - scoped supporter imports for supporter-entry roles
  - reports access for coordinators with constrained report scope

### Important reality check

The app now satisfies most of Becky’s everyday intake and follow-up needs.

The election-day poll watcher clarification from Becky is now partially implemented on the current branch:

- poll watcher tools now use full-GEC-voter turnout marking first
- a completed GEC import can be activated as the election-day voter list
- explicit poll watcher precinct assignments can narrow live election-day scope
- supporter GOTV is derived as an overlay on top of that full voter turnout list
- unmatched supporters are separated into an exception bucket for manual matching or operations follow-up
- remaining work is rollout hardening: realistic precinct QA, operations language, operator training, and rehearsal sign-off

The full-voter-list workflow should not be considered complete until that rollout evidence is captured.

### Remaining Becky work

#### Still meaningful

- Phase 2B ownership and follow-up history:
  - optional assignment / owner model for registrar or operations follow-up
  - clearer structured history for operational follow-up work
- Phase 2C operational rollups:
  - rollups for support-request types
  - rollups for follow-up outcomes
  - unresolved queue reporting by village / precinct where useful
- Phase 3 election-day workflow:
  - realistic QA for the full GEC voter-list poll watcher workflow
  - validation of supporter overlay results derived from full-voter turnout state
  - validation of war room queue counts driven from that overlay
  - election-day hardening and rehearsal

#### Nice-to-have / cleanup

- final QA sweep across Becky surfaces
- decide whether Becky-specific rollups should surface in quota summaries
- confirm whether committee leads need direct scoped access or only exported / shared handoff reports

## Recommended Implementation Order

## Phase 1A: Public intake expansion

Implement:

- 3-state registered-voter field
- conditional voting-location note
- help-request checkboxes
- optional referral fallback text

## Phase 1B: Structured household capture

Implement:

- repeatable household-member intake flow
- shared household contact/address model
- separate supporter records with household linkage

## Phase 1C: Staff visibility and reporting support

Implement:

- review/detail visibility
- useful filters
- useful reporting support for Becky follow-up workflows

## Recommended Next Implementation Order

### Phase 1 hardening

Mostly complete. Remaining items are QA / polish, not major feature gaps:

- full QA sweep across signup, review, detail, follow-up, and reporting surfaces
- decide whether Becky rollups belong in `Quota Summary` now or later

### Phase 2A: Dedicated follow-up queue

Implemented.

Delivered outcomes:

- clearer staff follow-up queue focused on actionability
- separation between registration follow-up and support-help follow-up
- stronger prioritization for unresolved Becky follow-up work
- improved row/card visibility for help requests and latest follow-up state

### Phase 2B: Ownership and follow-up history

Build after 2A:

- optional assignment / owner model for follow-up work
- structured follow-up history:
  - who updated
  - when
  - what changed
  - notes
- stronger supporter-detail activity visibility for operational follow-up

### Phase 2C: Operational rollups and reporting

Build after 2B:

- rollups for support-request types
- rollups for follow-up outcomes
- unresolved queue reporting
- village / precinct operational reporting where useful

### Phase 3A: Poll watcher voter-list foundation

Implemented on the current election-day branch:

- poll watcher access to the full GEC turnout list for assigned scope
- turnout marking against full voter list
- clear separation between full voter turnout and supporter overlay
- active election-day GEC import selection
- explicit poll watcher precinct assignments with assigned-village fallback

### Phase 3B: War room overlay workflow

Implemented on the current election-day branch:

- overlay campaign supporters on top of turnout data
- derive supporters who still need GOTV calls
- war room targeting and live queue visibility
- unmatched-supporter exception visibility for supporters without a clean GEC voter link

### Phase 3C: Election-day hardening

Remaining rollout work:

- role/scope hardening for poll watchers and war room staff
- stress testing
- conflict handling for turnout updates
- readiness QA for election-day operations

## PR / Branching Recommendation

### Recommended path

Do **not** try to land all remaining Becky work as one giant PR.

Instead:

1. treat `Phase 2B` ownership/history as the next Becky PR if campaign ops still wants in-app handoff ownership
2. follow with `Phase 2C` operational rollups/reporting if those rollups are needed before election-day
3. treat `Phase 3` full-voter poll watcher / war room overlay work as a separate election-day PR stream

### Why

- it keeps the branch reviewable
- it lowers regression risk
- it makes QA easier
- it avoids mixing daily follow-up workflow changes with election-day architecture changes

### Practical recommendation

The best next move is:

- keep this document aligned with shipped reality
- decide whether `Phase 2B` is still needed before election-day
- if not, skip straight to planning `Phase 3A` full-voter poll watcher foundation

## Data Model Direction

Exact schema names can change during implementation, but the direction should be:

### Public intake data

- `registered_voter_status`
  - `yes`
  - `no`
  - `not_sure`
- `registered_voter_location_note`
- help-request flags such as:
  - `wants_to_volunteer`
  - `needs_absentee_ballot_help`
  - `needs_homebound_voting_help`
  - `needs_voter_registration_help`
  - `needs_election_day_ride`
- optional `referred_by_name`

### Household data

Recommended concept:

- `household_group` or equivalent shared household model
- supporter records belong to a household group when applicable
- optional household-level shared contact fields if needed

## Open Questions To Confirm During Implementation

These do not block documentation, but should be answered while building:

- which household fields are truly household-level vs person-level?
- should each household member be able to override phone/email individually, or should that come later?
- should campaign-help checkboxes live directly on `supporters` or in a separate support-needs structure?
- should `Who referred you?` appear only when there is no referral code, or also as an optional supplemental field?
- what exact report/filter surface should be the first operational handoff tool for Becky / registrars?

## Recommended Working Rule

If the team is unsure during implementation, default to:

- structured fields over free text
- separate supporter records over combined household blobs
- visible staff follow-up data over hidden notes
- simpler phased delivery over one giant branch

## Summary

The Becky work is now mostly complete for:

- public intake expansion
- structured household intake
- staff visibility
- operational follow-up queues, filters, and exports

The main Becky requirement still needing rollout proof is the election-day clarification:

- turnout work is now based on the full GEC voter list in the current branch
- campaign GOTV action is now derived by overlaying supporter status on top of that full turnout data
- realistic precinct QA, operator training, and rehearsal sign-off still need to be captured
