# Supporter Intake Phase 1 Implementation Plan

**Status:** Proposed implementation plan  
**Date:** 2026-03-16  
**Depends on:** `docs/supporter-intake-and-review-workflow-plan.md`

## Goal

Implement Phase 1 of the supporter workflow redesign without losing current functionality or confusing the data team.

Phase 1 should correct the core workflow problem:

- nobody becomes an official supporter until the data team approves them
- public signups stay in their own first-stage queue
- approved public signups then move into the main review queue
- staff/manual/OCR/imported records go directly into the main review queue
- GEC match results support review, but do not replace data-team approval

## Current Product Gaps

The current codebase still reflects an older workflow in a few important places:

- staff-entered records are effectively accepted too early
- the main review queue is framed as a GEC follow-up queue instead of the real approval gate
- the supporters list is scoped around accepted intake instead of approved supporters
- reports are mostly download-first instead of preview-first
- public review currently moves records directly into the working supporter list

## Phase 1 Deliverables

### 1. Approval-gated supporter lifecycle

Introduce a true review lifecycle for supporter submissions.

Target behavior:

- new record created
- record sits in a pending review state
- data team approves or rejects it
- only approved records appear in official supporter views and counts

### 2. Public signup first-stage review stays separate

Public signups remain visible in their own `Public Signup Review` page first.

Target behavior:

- public submission created
- data team accepts or rejects at public-review stage
- accepted public signup moves into the main supporter review queue
- rejected public signup remains stored but excluded from operations

### 3. Main review queue becomes the real approval queue

Replace the current GEC-only mental model with a proper data-team review workspace.

Target behavior:

- queue includes all pending non-public-reviewed supporter submissions
- queue shows GEC match evidence, duplicates, geography, origin, and who submitted it
- actions are approval-oriented, not just GEC-oriented

### 4. Official supporter views use approved records only

Update:

- supporters list
- dashboard KPIs
- reports
- quota views
- any other operational count

So they are all based on approved supporters only.

### 5. Reports become preview-first

Users should be able to:

- open report in app
- filter it in app
- inspect rows in app
- export after preview

### 6. Public-site polish

- move staff portal link to subtle footer location
- remove public supporter counter

## Recommended Data Model Changes

This plan intentionally describes the model in business terms first. Exact column names can be finalized during implementation.

### Keep existing concepts

- `source`
- `attribution_method`
- `verification_status` only if repurposed or clarified to mean GEC review state

### Add or rename to a true review lifecycle

Recommended field:

- `review_status`
  - `pending`
  - `approved`
  - `rejected`

Recommended metadata:

- `reviewed_at`
- `reviewed_by_user_id`
- `review_notes`

### Clarify public-review stage

We still need a separate public intake stage, so we should retain or replace the current public-intake marker with something explicit.

Recommended approach:

- keep a dedicated public-review stage flag/status for public-origin records
- only after public approval should those records be eligible for the main review queue

Possible direction:

- `public_review_status`
  - `pending`
  - `approved`
  - `rejected`

This avoids overloading one field with two review stages.

### Separate GEC assessment from supporter approval

Recommended GEC-specific fields:

- `gec_match_status`
  - `exact_match`
  - `possible_match`
  - `ambiguous_match`
  - `no_match`
  - `referral_match`
- `matched_gec_voter_id`
- `gec_match_confidence`
- `gec_match_notes`

### Preserve rejected records

Rejected records stay in the main table and remain auditable.

They should:

- not count as official supporters
- remain filterable
- remain editable if a re-review flow is needed later

## Backend Implementation Plan

## Step 1: Migrations

Create migration(s) to introduce the new review lifecycle.

Recommended migration work:

- add `review_status`
- add `reviewed_at`
- add `reviewed_by_user_id`
- add `review_notes`
- add `public_review_status` if we separate first-stage public review cleanly
- add `gec_match_status`
- add `matched_gec_voter_id`
- add `gec_match_confidence`
- add `gec_match_notes`
- add indexes for common queue filters

Backfill strategy should be documented in the migration or accompanying notes.

Backfill goals:

- preserve current public-origin semantics
- avoid accidentally treating old accepted records as pending
- map existing accepted operational supporters into the new approved state
- map existing pending public signups into the new public-review pending state

## Step 2: Model updates

Primary file:

- `api/app/models/supporter.rb`

Changes:

- replace `accepted_intake` / `working_supporters` assumptions with new review-based scopes
- add new scopes for:
  - approved supporters
  - pending main review
  - rejected submissions
  - pending public review
  - approved public review awaiting main review
- ensure KPI-related scopes use approved supporters only

Potential new scopes:

- `approved_supporters`
- `pending_supporter_review`
- `rejected_submissions`
- `pending_public_review`
- `approved_public_intake`

## Step 3: Creation flow changes

Primary file:

- `api/app/controllers/api/v1/supporters_controller.rb`

Changes:

- on create, do not mark staff-created records as operationally accepted
- public signup create should remain separate but not become official supporter
- automatic duplicate detection and GEC matching can still run after create
- creation response should return review-state info needed by the frontend

Important rule:

- `auto_vet_against_gec` may still enrich the record, but it must not make the person effectively official

## Step 4: Public review endpoint changes

Primary endpoint:

- `GET /api/v1/supporters/public_review`
- `PATCH /api/v1/supporters/:id/accept_to_quota`

This action likely needs a clearer name, but can remain temporarily for compatibility if needed.

Target behavior:

- public review only handles first-stage intake decision
- accepting here should move record from `pending public review` to `ready for main supporter review`
- it must not make the record an official supporter
- rejecting here should keep the record stored with a rejected state

Possible future rename:

- `accept_public_submission`
- `approve_public_submission`

## Step 5: Main review queue endpoint redesign

Primary endpoint today:

- `GET /api/v1/supporters/vetting_queue`

This endpoint should be redesigned into the real approval queue.

Likely rename later:

- `supporter_review_queue`

Short-term compatibility option:

- keep the existing route but change behavior and frontend label

Required response payload should include:

- record identity and contact details
- origin
- submitted by
- created timestamp
- village / precinct / district
- duplicate indicators
- GEC match summary
- status values for:
  - public-review stage
  - main review stage
  - GEC match status

Required filters:

- village
- precinct
- district
- origin
- submitted_by
- GEC match status
- review status
- duplicate status
- date range or created date

Required actions:

- approve supporter
- reject supporter
- possibly mark as needs follow-up later

## Step 6: Approval/rejection actions

Add explicit actions for main review decisions.

Recommended endpoints:

- `PATCH /api/v1/supporters/:id/approve`
- `PATCH /api/v1/supporters/:id/reject`

These should:

- update `review_status`
- set reviewer metadata
- log audit events
- broadcast count updates if needed

## Step 7: Supporter list changes

Primary endpoint:

- `GET /api/v1/supporters`

Change default behavior so the main supporters list shows approved official supporters only.

Also add filters for:

- review status
- public review status where relevant
- rejected submissions if explicitly requested

## Step 8: Dashboard and KPI updates

Likely impacted backend files:

- `api/app/controllers/api/v1/dashboard_controller.rb`
- `api/app/controllers/api/v1/session_controller.rb`
- `api/app/controllers/api/v1/reports_controller.rb`
- any quota/report service using `working_supporters`

Rule:

- official KPI counts must use approved supporters only
- pending and rejected records should surface in review counters, not official totals

## Frontend Implementation Plan

## Step 1: Preserve Public Signup Review page

Primary file:

- `web/src/pages/team/TeamPublicReviewPage.tsx`

Change the meaning:

- this page remains first-stage review only
- accepting a public signup should send it to the main supporter review queue
- update copy so it no longer says `Accept to Supporter List`

Recommended wording:

- `Approve Public Submission`
- `Send To Supporter Review`

Summary cards should reflect:

- pending public submissions
- approved public submissions waiting for main review
- rejected public submissions

## Step 2: Replace the current vetting page concept

Primary file:

- `web/src/pages/team/TeamVettingPage.tsx`

Current problem:

- the page is framed as a GEC review queue for already accepted supporters

New goal:

- this becomes the true `Supporter Review Queue`

Suggested UI sections:

- queue summary
- filters
- primary record table/cards
- GEC evidence panel
- duplicate indicators
- approval and rejection actions

Suggested naming:

- `Supporter Review Queue`

GEC should still be visible, but as one part of the decision.

## Step 3: Update supporter detail page

Primary file:

- `web/src/pages/admin/SupporterDetailPage.tsx`

Needed changes:

- display review status separately from GEC match status
- show if record is pending, approved, or rejected
- show whether public review stage was completed
- show current GEC evidence
- keep audit clarity around who approved/rejected and when

## Step 4: Update supporters list page

Primary file:

- `web/src/pages/admin/SupportersPage.tsx`

Needed changes:

- main default view should represent official approved supporters
- allow optional filtering for rejected or pending submissions if desired
- clearly display origin, review status, and GEC status separately

## Step 5: Reports page redesign

Primary file:

- `web/src/pages/team/TeamReportsPage.tsx`

Current problem:

- download-first design

Phase 1 target:

- report picker
- in-app filter controls
- in-app report preview table/list
- export button after preview

Required filters:

- village
- precinct
- district

Future note should be visible in docs only for now, not necessarily in UI:

- report layout may later be aligned exactly to Rose's preferred examples

## Step 6: Routing and navigation updates

Primary file:

- `web/src/App.tsx`

Likely changes:

- route labels may change while paths can stay stable initially
- `/data/vetting` can continue existing as a route for compatibility, but should render the new `Supporter Review Queue`
- `Public Signup Review` remains separate

Likely navigation changes:

- rename menu item from `Voter Check Queue` to `Supporter Review Queue`
- ensure session badges reflect the new pending-review counts correctly

## Step 7: Public landing page polish

Likely impacted files:

- `web/src/pages/LandingPage.tsx`
- any public layout/footer components

Changes:

- move staff portal link to subtle footer location
- remove public supporter counter

## Reports API Plan

Current routes:

- `GET /api/v1/reports`
- `GET /api/v1/reports/:report_type`

Phase 1 enhancement:

- keep export endpoint behavior
- add preview-friendly response mode or dedicated preview endpoint

Possible approach:

- `GET /api/v1/reports/:report_type?preview=true`
- or `GET /api/v1/reports/:report_type/preview`

Preview payload should include:

- report metadata
- applied filters
- preview rows
- total row count
- column definitions if helpful

## Testing Plan

## Backend tests

Add/update tests for:

- public signup remains pending public review first
- public approval moves to main supporter review, not official supporter list
- staff entry goes to main supporter review, not official supporter list
- approved supporter appears in supporter list and KPI totals
- rejected supporter remains stored but excluded from official totals
- queue filters for village, precinct, district, origin, and GEC status
- reports preview respects filters

Likely impacted test files:

- `api/test/controllers/api/v1/supporters_controller_test.rb`
- `api/test/controllers/api/v1/reports_controller_test.rb`
- `api/test/controllers/api/v1/dashboard_controller_test.rb`
- `api/test/controllers/api/v1/session_controller_test.rb`
- service tests for any GEC-review mapping helpers introduced

## Frontend verification

Verify manually:

1. public signup appears in `Public Signup Review`
2. approving there moves it to `Supporter Review Queue`
3. approving in main review adds it to official supporters
4. rejecting at either stage keeps the record stored but excluded
5. staff manual entry goes straight to `Supporter Review Queue`
6. supporter list excludes pending/rejected by default
7. reports preview matches filters before export
8. public page shows subtle staff portal link and no supporter count

## Rollout Strategy

Recommended order of implementation:

1. schema + model changes
2. controller/API behavior changes
3. queue UI changes
4. supporter list and KPI corrections
5. reports preview
6. public-site polish

Do not start Phase 2 VO batching until Phase 1 behavior is stable and tested.

## Phase 2 Reminder

Phase 2 is intentionally separate.

It should introduce:

- village-org intake queue
- grouping by submitter or submission batch
- explicit movement from VO intake into main supporter review
- preserved row order

That should not be mixed into Phase 1 unless absolutely necessary.

## Files Most Likely To Change

Backend:

- `api/app/models/supporter.rb`
- `api/app/controllers/api/v1/supporters_controller.rb`
- `api/app/controllers/api/v1/dashboard_controller.rb`
- `api/app/controllers/api/v1/session_controller.rb`
- `api/app/controllers/api/v1/reports_controller.rb`
- new migration file(s)
- related tests under `api/test/controllers/...`

Frontend:

- `web/src/pages/team/TeamPublicReviewPage.tsx`
- `web/src/pages/team/TeamVettingPage.tsx`
- `web/src/pages/team/TeamReportsPage.tsx`
- `web/src/pages/admin/SupportersPage.tsx`
- `web/src/pages/admin/SupporterDetailPage.tsx`
- `web/src/App.tsx`
- public landing/footer component(s)
- `web/src/lib/api.ts`

## Open Questions To Resolve During Implementation

These are smaller implementation questions, not blockers to the overall workflow:

- final field names for review lifecycle
- whether to rename `verification_status` or keep it for compatibility
- whether public rejection should use the same rejected state as main review or a stage-specific rejected state
- whether the main review action wording should be `Approve Supporter` or `Add To Official Supporter List`
- whether district filtering should happen via joins or precomputed supporter geography helpers
