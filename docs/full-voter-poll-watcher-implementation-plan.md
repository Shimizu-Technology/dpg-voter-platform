# Full-Voter Poll Watcher Implementation Plan

**Status:** Phase 3A foundation implemented on current branch; rollout hardening remains  
**Date:** 2026-04-20  
**Owner:** Campaign Tracker team

## Purpose

This document turns Becky’s election-day clarification into an implementation plan.

It exists to answer:

- what exactly are we building next?
- what decisions are already locked?
- what is included in `Phase 3A` versus deferred to later election-day work?

## Product Problem

The app previously shipped a supporter-level poll watcher strike list.

That was useful, but it did **not** match Becky’s actual election-day workflow. The current branch now implements the corrected full-voter workflow foundation, including active election-day list selection, explicit precinct assignment scope, supporter overlay, war-room derived queues, and unmatched-supporter exception visibility. It still needs realistic precinct QA, operator training, and rehearsal sign-off before it should be treated as fully rollout-ready.

Becky’s requirement is:

1. poll watchers work from the full assigned GEC voter list
2. turnout is marked against that voter universe first
3. campaign supporter status is overlaid on top of that turnout data
4. war room uses the derived list of supporters who still have not voted

This distinction matters because poll watchers hear and mark every voter in the precinct, not just campaign supporters.

## Locked Product Decisions

The following decisions are now treated as confirmed unless campaign ops explicitly changes them:

### 1. Source of truth for election-day voter universe

- Poll watchers should see the full GEC voter list for their assigned scope.
- Before live election-day use, the campaign should activate the final authoritative completed `gec_import` as the election-day list.
- If no import has been explicitly activated, the app falls back to the latest active GEC list date so non-live environments remain usable.

### 2. Scope model

- Poll watchers should operate on assigned precinct scope.
- The branch supports explicit poll-watcher-to-precinct assignments for live operations.
- Assigned-village scope remains as a fallback for existing accounts until explicit assignments are loaded.
- Broader roles such as village chief, district coordinator, campaign admin, or war room staff may have wider visibility based on role.

### 3. Full-voter workflow first

- Turnout tracking is based on `gec_voters`, not supporter records.
- Supporter records should be shown as an overlay or derived subset, not as the primary strike list.

### 4. Narrow poll watcher permissions in v1

For `Phase 3A v1`, poll watchers should be able to:

- view assigned precinct voter list
- mark turnout for those voters
- submit precinct turnout snapshots / issue reports

For `Phase 3A v1`, poll watchers should **not** be responsible for the full war-room outreach workflow unless required later.

### 5. Core turnout states

- `unknown`
- `not_yet_voted`
- `voted`

These are sufficient for the first full-voter foundation.

### 6. Conflict model

- Last write wins.
- Every turnout change must be fully auditable with actor and timestamp.

### 7. Derived war room queue

- War room should consume supporters who are both:
  - campaign supporters
  - and currently `not_yet_voted` in the full-voter turnout state
- Supporters without a clean `gec_voter` link should be shown in a separate unmatched bucket, not counted as part of the full-voter-derived queue.

## Why This Direction Is Correct

This approach matches both Becky’s explanation and standard campaign GOTV practice:

- field teams mark turnout against precinct voter rolls
- support data is layered on top
- outreach targets are derived from the intersection of supporter identity and outstanding turnout

If the app only shows campaign supporters to poll watchers, it skips the real working list and forces staff back into manual reconciliation.

## Phase 3A Goal

Deliver the full-voter poll watcher foundation.

This phase should make the election-day data model honest and operationally correct, without trying to solve every downstream war-room optimization in the same PR.

## Included In Phase 3A

### 1. Data model foundation

Implemented:

- full-voter turnout tracking tied to `gec_voters`
- audit-safe turnout updates
- linkage or derivation path from `gec_voters` to matched campaign supporters
- explicit active election-day import fields on `gec_imports`
- explicit poll watcher precinct assignments

Expected result:

- turnout is no longer stored only on supporter records for poll watcher workflow
- campaign supporter overlay can be derived from existing vetting/matching data

### 2. Backend API

Implemented:

- precinct-scoped full-voter strike-list fetch
- turnout update endpoint(s) for `gec_voters`
- responses that include supporter overlay metadata when a voter is also a campaign supporter
- admin activation endpoint for completed election-day GEC imports
- war-room queue payloads for matched not-yet-voted supporters and unmatched supporters

Expected result:

- client can render the full list of assigned voters
- client can visibly distinguish supporter vs non-supporter voters

### 3. Poll watcher UI

Implement:

- mobile-first full-voter strike-list
- fast turnout marking
- supporter overlay indicators on voter rows/cards
- clear distinction between:
  - turnout tracking
  - supporter follow-up relevance

Expected result:

- watcher can work from the same functional list concept Becky described

### 4. War room derivation foundation

Implemented:

- derived queue of supporters who are still `not_yet_voted`
- basic counters / visibility that are based on the full-voter turnout state, not supporter-only turnout state
- unmatched-supporter exception bucket for supporters without a GEC voter link

Expected result:

- war room targeting logic is based on the correct election-day source data

### 5. Tests and QA

Implement:

- role/scope coverage
- turnout update coverage
- supporter-overlay derivation coverage
- manual simulation checklist for one full precinct flow

## Not Included In Phase 3A

These should be deferred unless they are required to make the core workflow usable:

- offline-first sync / queued reconciliation
- advanced outreach outcome workflows inside poll watcher UI
- assignment / owner model for Becky’s non-election-day follow-up work
- expanded operational rollups unrelated to election-day turnout foundation
- broad war room redesign beyond what is required for the derived supporter queue

## Decisions Resolved During Build

### 1. Final election-day list freeze

- The app now has an explicit `active_election_day` flag on completed `gec_imports`.
- Only one import can be active for election-day use at a time.
- Strike-list and war-room derivation use the active import's `gec_list_date` when one is set.

### 2. Multi-watcher precinct conflicts

- Can more than one watcher update the same precinct at once?
- If yes, is audit trail + last-write-wins enough for v1?

### 3. Snapshot cadence

- Are turnout snapshots submitted hourly, every two hours, or ad hoc?
- Does ops want any required cadence enforcement in the UI?

### 4. Outreach ownership

- Should poll watchers only mark turnout in v1?
- Should supporter outreach remain a war room action driven by the derived queue?

### 5. Unmatched supporter handling

- Supporters with no clean `gec_voter` link are excluded from the full-voter-derived "not yet voted" queue.
- They are surfaced separately as an unmatched-supporter bucket for manual matching or operations follow-up.

## Open Questions To Confirm During Rollout

These remain operational decisions, not implementation blockers for the current branch:

- Can more than one watcher update the same precinct at once, and is audit trail plus last-write-wins enough for live use?
- Are turnout snapshots submitted hourly, every two hours, or ad hoc?
- Should supporter outreach remain war-room-owned, or should poll watchers perform any outreach on election day?

## Recommended Technical Shape

### Backend

- keep `Supporter` turnout fields for legacy/supporter-only flows only if needed during migration
- introduce full-voter turnout storage centered on `gec_voters`
- derive supporter overlay via supporter-to-GEC relationship or lookup based on existing vetting links

### Frontend

- replace supporter-only poll watcher list with full-voter list
- add a supporter badge / overlay section in each voter row
- ensure the war room queue reads from derived supporter overlay results

### Rollout

1. build `Phase 3A` foundation first
2. run election-day rehearsal with realistic voter data
3. only then decide whether additional `3B` / `3C` work is needed before live use

## Acceptance Criteria

`Phase 3A` is complete when:

- poll watcher can view the full assigned GEC voter list
- poll watcher can mark turnout against that full list
- supporter overlay is visible for matched supporters
- war room can derive a queue of supporters who have not yet voted
- all updates are role-scoped and auditable
- manual simulation demonstrates the workflow Becky described without requiring manual paper reconciliation

## Immediate Next Build Sequence

1. Load or confirm the final authoritative GEC import and activate it for election-day use.
2. Load explicit poll watcher precinct assignments for the live operations roster.
3. Run realistic precinct QA against assigned watcher accounts, chiefs, coordinators, and admins.
4. Validate the matched supporter queue and unmatched-supporter exception bucket against campaign expectations.
5. Complete operator training and capture rehearsal evidence in the readiness checklist.
