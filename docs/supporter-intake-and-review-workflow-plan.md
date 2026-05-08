# Supporter Intake And Review Workflow Plan

**Status:** Approved planning document  
**Date:** 2026-03-16  
**Owner:** Campaign Tracker team

## Purpose

This document is the source of truth for the next supporter-workflow redesign.

It captures:

- what the campaign team wants
- what the app does today
- what is wrong with the current flow
- what Phase 1 must change
- what belongs in Phase 2
- how reporting, vetting, and backups should work

This document should be referenced while implementing the workflow and when revisiting decisions later.

## Why This Needs To Change

The current app behavior is still too permissive.

Today, some records can effectively become operational supporters too early, especially staff-entered records. The campaign team clarified that this is not the desired workflow.

The real business rule is:

- no one should become an official supporter until the data team reviews and approves them
- GEC matching is important evidence, but it is not the final approval gate
- public signups must still remain in their own separate intake queue before they move into the main review flow
- rejected records should stay in the system for auditability and follow-up, but should not count anywhere operationally

## Confirmed Workflow Decisions

These decisions are considered confirmed unless the campaign team explicitly changes them later.

### 1. Official supporters require data-team approval

- A person is not part of the real supporter list just because they were entered into the system.
- A person is not part of the real supporter list just because they matched the GEC voter list.
- The data team must review and approve the record first.

### 2. GEC status and supporter approval are separate concepts

- `Supporter approval` answers: should this person be accepted into the campaign's official supporter list?
- `GEC status` answers: how well does this person match the latest GEC voter data?

These must not be collapsed into the same concept.

### 3. Public signups stay separate first

For now, public signups should remain in a dedicated `Public Signup Review` queue.

Flow:

1. person submits from the public-facing site
2. record appears in `Public Signup Review`
3. data team approves or rejects that public submission
4. if approved, it moves into the main supporter-review queue
5. only after the main review flow is completed should the person become an official supporter

This is intentionally more redundant than the ideal long-term design, but it matches the current campaign request.

### 4. Rejected submissions stay in the system

- Rejected records should remain stored
- They should be filterable later by `rejected`
- They should not appear in the official supporter list
- They should not count toward dashboards, reports, quotas, or operational totals

### 5. The main review queue is not only for no-match records

The main review queue must be for all pending supporter submissions that need data-team review.

That includes people who:

- match GEC exactly
- partially match GEC
- do not match GEC
- appear ambiguous
- look like referrals
- may be duplicates

The queue is not just a cleanup list for exceptions. It is the approval gate.

### 6. Reports need in-app preview, not just export

The campaign team wants to see the report on the website before downloading/exporting it.

Required behavior:

- users can open a report in the app
- users can filter it in the app
- users can inspect the actual rows in the app
- users can then export/download if needed

### 7. The public site should reveal less

Immediate public-site updates:

- move the staff portal link to a subtle footer placement
- remove the public supporter counter

### 8. Backups are a real operational requirement

Production runs on Neon, but the team wants independent backups.

The goal is nightly automatic backups with retention and a documented restore path.

## Current State Vs Target State

### Current state

- Public-origin records can be held in `Public Signup Review`
- Staff-entered records are effectively treated as accepted too early
- The current main vetting flow is centered too heavily around GEC follow-up
- The supporters list is still too tied to earlier acceptance assumptions
- Reporting is still too export-first

### Target state

- every new person starts as a submission under review
- public-origin records first pass through `Public Signup Review`
- after public approval, they move into the main review queue
- staff/manual/OCR/imported records go into the main review queue directly
- no one becomes an official supporter until approved by the data team
- official supporter views only show approved supporters
- GEC results enrich the review process but do not replace approval

## Phase 1 Scope

Phase 1 is the immediate workflow correction that should be built next.

### Phase 1 goals

- enforce a true data-team approval gate
- keep public signups in their own initial queue
- create a real main supporter review queue for all pending non-public-reviewed approvals
- separate supporter approval from GEC match results
- keep rejected records for audit/history
- update reports to support in-app preview and better filters
- make the staff portal less visible on the public site
- remove the public supporter counter

### Phase 1 target flow

#### Public signup flow

1. public user submits a signup
2. record enters `Public Signup Review`
3. data team approves or rejects the submission
4. if approved, it moves into the main `Supporter Review Queue`
5. data team reviews the supporter with GEC evidence and other context
6. if approved there, the person becomes an official supporter
7. if rejected, the record remains stored but excluded from official views

#### Staff entry / OCR / Excel import flow

1. staff adds the person through manual entry, OCR, or import
2. record goes directly into the main `Supporter Review Queue`
3. system computes GEC hints, duplicate hints, and metadata
4. data team approves or rejects
5. approved record becomes an official supporter

### Phase 1 main queue behavior

The new main queue should be treated as the data-team approval workspace.

It should allow filtering by at least:

- GEC match status
- village
- precinct
- district
- origin
- submitted by
- duplicate status
- review status
- created date

Each row should show enough information for a meaningful decision, including:

- supporter name
- origin
- who entered/submitted it
- village
- precinct
- district if available
- contact details
- DOB / birth year if available
- duplicate warning
- GEC summary
- exact / possible / ambiguous / no-match indication
- created timestamp

### Phase 1 official-list rule

The real supporter list, dashboard totals, quota metrics, and operational reports should use only approved supporters.

Pending and rejected submissions must be excluded from:

- official supporter counts
- quota-eligible counts
- verified totals
- village quota progress
- data-ops operational lists unless explicitly filtered for review purposes

## Recommended Data Model Direction

This section describes the intended model direction. Exact column names can change during implementation, but the separation of concepts should remain.

### Keep `origin`

Keep an immutable field that answers where the record came from.

Examples:

- `public_signup`
- `qr_signup`
- `staff_entry`
- `bulk_import`

Later, additional source/origin values may be added for village-org submission channels.

### Replace acceptance-only logic with a true review status

The app needs a review lifecycle that represents approval by the data team.

Recommended concept:

- `review_status`
  - `pending`
  - `approved`
  - `rejected`
  - optional future state: `needs_follow_up`

This status should control whether a record is considered an official supporter.

### Separate GEC matching into its own field(s)

Recommended concept:

- `gec_match_status`
  - `exact_match`
  - `possible_match`
  - `ambiguous_match`
  - `no_match`
  - `referral_match`

Recommended supporting fields:

- `matched_gec_voter_id`
- `gec_match_confidence`
- `gec_match_notes`
- optional `gec_reviewed_at`
- optional `gec_reviewed_by_user_id`

This allows the app to show how well the record aligns with GEC data without confusing that with supporter approval.

### Rejected records remain first-class data

Rejected records should not be deleted just because they do not become official supporters.

They should remain:

- auditable
- searchable
- editable if staff needs to correct and re-review them later

## Queue Architecture

### Public Signup Review

This remains separate for now because the campaign explicitly wants it separate.

It should answer:

- which public submissions are still waiting for initial intake review?
- which were approved to move into the main supporter review process?
- which were rejected?

### Main Supporter Review Queue

Suggested name:

- `Supporter Review Queue`

This queue is the actual approval gate before someone becomes an official supporter.

It should include:

- approved public signups waiting for main review
- staff manual entries
- OCR entries
- Excel import entries
- future approved VO-submitted batches when Phase 2 is implemented

This queue should not be named in a way that implies it only contains no-match records.

## Reports Requirements

### Phase 1 reporting behavior

Reports should be visible on-site before export.

Core expectations:

- preview in the app
- filters in the app
- export after preview

### Required filters

- village
- precinct
- district
- report type
- date range where relevant

### Report categories to support

Near-term reporting should support at least:

- official supporter list
- not registered / no GEC match list
- referral list
- newly registered list
- quota progress reports
- village reports
- precinct reports
- district reports

### Future note

When Auntie Rose shares the report examples she is already used to, the app's outputs should be updated to match those formats as closely as possible.

## Phase 2 Scope

Phase 2 is the village-org intake architecture.

The purpose is to prevent the data team from seeing one giant undifferentiated pile of incoming village-org submissions.

### Phase 2 goals

- separate village-org-submitted entries from the main queue until the data team is ready
- group submissions by submitter and context
- preserve upload/input order
- let the data team choose which batch/group to move into the main review queue

### Phase 2 desired behavior

When a village chief or similar non-data-team role uploads/adds supporters:

- the records should not drop directly into the main review queue
- instead they should land in a `VO Intake Queue`
- the queue should group them by submitter or submission batch
- the data team should be able to open a group and then move that group into the main review queue when ready

Example grouping:

- submitter name
- village
- role
- submission timestamp
- channel used
- row count

### Phase 2 ordering requirement

The village-org list must preserve row order.

Reason:

- the data team may receive physical blue forms in the same order
- when reviewing the digital list against paper, the rows need to appear in that same sequence

Recommended future fields:

- `submission_batch_id`
- `batch_position`
- optional `paper_page_number`
- optional `paper_line_number`
- optional `quota_submission_label`

## Backup Plan

This is an operational requirement and should be tracked alongside product work.

### Backup goal

Have an automatic nightly backup path independent from the live Neon database.

### Recommended approach

- run nightly Postgres backups
- store them in separate cloud storage
- keep retention for daily, weekly, and monthly restore points
- verify restore steps periodically

### Minimum expectations

- nightly automatic job
- failure alerting
- documented restore procedure
- at least one successful restore test in a non-production environment

## Metrics And KPI Rules

Once this workflow is implemented, KPI rules should become much simpler and more honest.

### Official counts should use approved supporters only

This includes:

- total active supporters
- total verified supporters
- quota eligible
- village quota progress
- district and precinct supporter totals

### Pending and rejected records should be separate

The app should expose pending and rejected volumes clearly, but they should not inflate official totals.

Examples:

- pending public submissions
- pending supporter reviews
- rejected submissions
- no-match submissions
- referral submissions

## Out Of Scope For This Plan

The unrelated form on `joshtina.info` is not part of this app's implementation scope.

The campaign team should handle that separately.

This app only needs to ensure that its own public flow and staff access flow are clear and correct.

## Implementation Notes

The exact table and endpoint design may evolve, but the following architectural rules should stay stable:

- approval must be separate from GEC match logic
- public signup review stays separate first
- official supporters must be approval-gated
- rejected records stay stored
- reports must be previewable in-app
- VO intake batching is a Phase 2 feature
- row order preservation for VO batches is required when that phase is implemented

## Immediate Next Build Priorities

Recommended implementation order:

1. introduce the new approval-gated review model
2. rebuild the main review queue around approval plus GEC evidence
3. keep public signup review as the first-stage queue for public-origin records
4. update supporter lists, dashboards, and KPIs to use approved supporters only
5. upgrade reports to support in-app preview and richer filters
6. move the staff portal link and remove the public supporter counter
7. design and build the Phase 2 VO intake batching system
8. implement nightly backup automation and restore validation

## Related Documents

- `docs/future-supporter-workflow-followups.md`
- `docs/gec-import-transparency-viewer-plan.md`
- `docs/rbac-matrix.md`
