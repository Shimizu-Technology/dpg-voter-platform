# Campaign Tracker Execution Tracker

Last updated: 2026-02-13  
Purpose: single operational checklist for what is done, what is in progress, and what comes next.

---

## How to Use This

- Move items between sections as work progresses.
- Keep status labels current: `todo`, `in_progress`, `blocked`, `done`.
- Only mark `done` when acceptance criteria are met.
- Keep detailed execution tasks in this file (avoid creating parallel task lists).

---

## Done

### Core Product Foundations
- [x] Public supporter signup flow (`/signup`) implemented.
- [x] Staff supporter entry flow (`/admin/supporters/new`) implemented.
- [x] Supporter listing with filters and mobile improvements implemented.
- [x] Village detail to supporters drill-down flow implemented.
- [x] Precinct assignment workflow for unassigned supporters implemented.
- [x] Dynamic back/home navigation improvements implemented.
- [x] Admin user management page implemented (`/admin/users`) with role assignment.
- [x] Dashboard top navigation redesigned to reduce congestion and improve discoverability.
- [x] Mobile user management layout updated to card-based rows for readability.
- [x] Global frontend baseline updated (brand typography, card primitives, focus styles) for cross-page consistency.
- [x] Key supporter/admin screens aligned to design system (`/admin`, `/admin/supporters`, `/admin/supporters/:id`, `/admin/users`).

### Supporter Detail + Tracking
- [x] Supporter profile page route implemented (`/admin/supporters/:id`).
- [x] Show-first UX with explicit edit mode (`Edit` -> `Save` / `Cancel`) implemented.
- [x] Unsaved-changes guard for back/home/cancel/browser-close implemented.
- [x] Basic audit log model/table integrated and displayed on supporter detail.

### Security / Stability / Quality
- [x] Auth sync/reload-loop issues resolved.
- [x] ActionCable authentication hardened.
- [x] SMS authorization tightened (coordinator-or-above for high-impact sends).
- [x] Source attribution logic improved for staff vs public flow.
- [x] CI/lint/build/test baseline repaired and passing for current changes.
- [x] Admin-only API guard added for user management endpoints.

---

## Now (Current Priority)

### 1) Role-Gated Supporter Editing
- Status: `done` (2026-02-13)
- Goal: restrict who can edit supporter records while keeping read access for staff.
- Scope:
  - Backend authorization on supporter update endpoint.
  - Frontend edit controls hidden/disabled for unauthorized roles.
  - Clear UX message for read-only users.
- Acceptance criteria:
  - Unauthorized roles receive `403` on update attempts.
  - Authorized roles can edit and save successfully.
  - Automated tests cover allowed and forbidden cases.

### 2) Audit Log Depth Improvement
- Status: `done` (2026-02-13)
- Goal: make audit history operationally useful.
- Scope:
  - Store field-level diffs (`from` -> `to`) for updates.
  - Include actor role + action label in response/UI.
  - Keep list ordered by newest first.
- Acceptance criteria:
  - Every supporter edit produces a readable diff entry.
  - UI clearly shows who changed what and when.
  - Backend tests verify audit payload shape.

### 3) Core Flow Verification Pass
- Status: `in_progress`
- Goal: verify end-to-end real workflow on desktop + mobile.
- Scope:
  - Public signup -> supporter appears in admin.
  - Assignment/edit on supporter detail.
  - Audit entry appears immediately after save.
- Acceptance criteria:
  - Full checklist passes with no blocking defects.
  - Note: automated API/unit checks are passing; manual desktop/mobile run-through pending.
- Verification log (2026-02-13):
  - Automated checks: `rails test` (supporters controller), `eslint`, and `vite build` all passed.
  - API/auth behavior seen in logs:
    - Supporter detail endpoint returns `200` when authenticated.
    - Endpoint returns `401` when token/session is missing/expired (expected).
  - Pending manual browser pass (desktop + mobile):
    1. Public signup creates supporter and appears in admin list.
    2. Supporter detail opens in read-only mode by default.
    3. Role-gated edit behavior:
       - admin/coordinator can edit + save
       - non-editor roles see read-only notice and cannot edit
    4. Save action creates audit entry with readable field-level `from` -> `to` diffs.
    5. Back/Home navigation and unsaved-change guard behave correctly.

---

## Next (After Now Is Stable)

### 4) Legacy Source Backfill (Safe Cleanup)
- Status: `todo`
- Scope:
  - Add dry-run backfill task for historical supporter `source` values.
  - Review output before applying.
- Acceptance criteria:
  - Dry-run report reviewed and approved.
  - Apply run completes with summary counts.

### 5) Performance Hardening
- Status: `todo`
- Scope:
  - Add short-lived dashboard caching.
  - Profile and optimize war-room endpoint.
  - Validate/add DB indexes for frequent filters and sorts.
- Acceptance criteria:
  - Measurable reduction in response time/query count on target endpoints.

### 6) E2E Smoke Automation
- Status: `todo`
- Scope:
  - Add one browser E2E happy-path smoke test.
- Acceptance criteria:
  - CI can run a basic critical-flow test successfully.

### 7) Election-Day Strike List Flow (Supporter-Level Turnout)
- Status: `done` (engineering scope complete 2026-02-13)
- Goal: support campaign-grade election-day GOTV operations with supporter-level "voted / not yet voted" tracking.
- Scope:
  - Add supporter-level election-day turnout status (campaign-tracked, not official election records).
  - Add poll watcher strike-list workflow by precinct for marking turnout events.
  - Feed supporter-level turnout into war room queues for "not yet voted" outreach.
  - Add contact outcome logging for call attempts during GOTV push.
  - Add audit trail + role guardrails for all turnout status changes.
- Acceptance criteria:
  - Poll watcher can update turnout status for assigned precinct supporter records.
  - War room shows actionable "not yet voted" call lists by village/precinct.
  - Updates are role-gated, auditable, and visible in near real-time.
  - Manual verification checklist passes for one full election-day simulation flow.
- Scope boundary note:
  - This shipped item is the supporter-level turnout flow only.
  - It does **not** satisfy Becky’s later clarification that poll watchers must work from the full GEC voter list first and derive supporter follow-up as an overlay on top of that full voter universe.
- Implementation task breakdown:
  - **7.0 Poll watcher operations spec**
    - Status: `done` (2026-02-13)
    - Created role/workflow specification document for election-day watcher duties and war-room handoff expectations.
    - Reference:
      - `docs/poll-watcher-operations-spec.md`
    - Acceptance: app implementation can proceed using one shared operations source-of-truth.
  - **7.1 Data model + migration**
    - Status: `done` (2026-02-13)
    - Add supporter election-day turnout fields (campaign-tracked status, updated-at, updated-by, source).
    - Add call/contact outcome model or structured fields for GOTV follow-up attempts.
    - Acceptance: migrations run cleanly; schema supports per-supporter turnout + outreach tracking.
  - **7.2 Backend API for strike list**
    - Status: `done` (2026-02-13)
    - Add endpoint(s) to fetch precinct-scoped supporter strike list with filters.
    - Add endpoint(s) to mark supporter turnout status and log outreach outcomes.
    - Enforce strict role/scope checks (poll watcher/chief/coordinator/admin as intended).
    - Acceptance: authorized roles can read/update assigned scope; unauthorized requests return `403`.
  - **7.3 Audit + compliance guardrails**
    - Status: `done` (2026-02-13)
    - Log every turnout/outreach status change with actor + before/after values.
    - Add metadata note that data is campaign operations tracking (not official election records).
    - Acceptance: every status change produces an auditable record; compliance note appears in relevant UI.
  - **7.4 Poll watcher UI (field workflow)**
    - Status: `done` (2026-02-13)
    - Build mobile-first strike-list interface by precinct.
    - Fast status toggles for voted/not yet voted and contact outcomes.
    - Acceptance: watcher can process a full precinct list efficiently on mobile.
  - **7.5 War room queue integration**
    - Status: `done` (2026-02-13)
    - Add "not yet voted" queue panels by village/precinct with prioritization.
    - Surface outreach progress counters (remaining, attempted, reached).
    - Acceptance: war room reflects strike-list updates in near real-time.
  - **7.6 Test coverage + QA pass**
    - Status: `done` (2026-02-13)
    - Add controller/model tests for scope, permissions, and audit logging.
    - Run manual simulation: watcher updates -> war room queue updates -> outreach logging.
    - Acceptance: automated tests pass + manual simulation checklist completes without blockers.
  - **7.7 Rollout + operations readiness**
    - Status: `done` (2026-02-13)
    - Create lightweight operator guide for election-day use.
    - Confirm role assignments and precinct mappings before live usage.
    - Acceptance: campaign staff can execute a rehearsal without engineering intervention.
- 7.1 implementation notes (2026-02-13):
  - Added supporter turnout tracking fields:
    - `supporters.turnout_status` (`unknown`, `not_yet_voted`, `voted`)
    - `supporters.turnout_updated_at`
    - `supporters.turnout_updated_by_user_id`
    - `supporters.turnout_source` (`poll_watcher`, `war_room`, `admin_override`)
    - `supporters.turnout_note`
  - Added turnout-focused indexes:
    - `supporters(turnout_status)`
    - `supporters(precinct_id, turnout_status)`
  - Added contact outcome model/table:
    - `supporter_contact_attempts` with `supporter_id`, `recorded_by_user_id`, `outcome`, `channel`, `recorded_at`, `note`
  - Added model wiring/validations:
    - `Supporter`: turnout status/source validations + associations
    - `SupporterContactAttempt`: outcome/channel/recorded_at validations
    - `User`: reverse associations for turnout updates and contact attempts
- 7.1 verification log (automated):
  - `bundle exec rails db:migrate` -> pass
  - `bundle exec rails test test/models/supporter_turnout_tracking_test.rb test/controllers/api/v1/supporters_controller_test.rb` -> pass
- 7.2 implementation notes (2026-02-13):
  - Added strike-list API endpoints under poll watcher controller:
    - `GET /api/v1/poll_watcher/strike_list?precinct_id=:id` (optional: `turnout_status`, `search`)
    - `PATCH /api/v1/poll_watcher/strike_list/:supporter_id/turnout`
    - `POST /api/v1/war_room/supporters/:supporter_id/contact_attempts`
  - Scope enforcement:
    - All strike-list operations require precinct access through role-based precinct scope.
    - Unauthorized precinct access returns `403` (`precinct_not_authorized`).
    - Supporters are resolved inside scoped precinct only.
  - Turnout updates:
    - records `turnout_status`, `turnout_note`, `turnout_updated_at`, `turnout_updated_by_user_id`, and derived `turnout_source`.
  - Contact attempt logging:
    - creates `supporter_contact_attempts` entries with outcome/channel/note/timestamp and actor.
- 7.2 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/poll_watcher_controller_test.rb test/controllers/api/v1/supporters_controller_test.rb test/models/supporter_turnout_tracking_test.rb` -> pass
- 7.3 implementation notes (2026-02-13):
  - Added turnout audit logging in poll watcher strike-list flow:
    - action: `turnout_updated`
    - actor: current authenticated user
    - changed_data: normalized field-level `from` -> `to` for turnout fields
    - metadata: `resource`, `precinct_id`, `turnout_source`, `compliance_context`
  - Added contact-attempt audit logging:
    - auditable: `SupporterContactAttempt`
    - action: `created`
    - changed_data: normalized payload fields (outcome/channel/note/recorded_at/supporter_id)
    - metadata: `resource`, `precinct_id`, `compliance_context`
  - Added compliance note in strike-list related API responses:
    - `"Campaign operations tracking only; not official election records."`
  - Added `SupporterContactAttempt` -> `AuditLog` polymorphic association.
- 7.3 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/poll_watcher_controller_test.rb test/models/supporter_turnout_tracking_test.rb` -> pass
  - `bundle exec rails test test/controllers/api/v1/poll_watcher_controller_test.rb test/controllers/api/v1/supporters_controller_test.rb test/models/supporter_turnout_tracking_test.rb` -> pass
- 7.4 implementation notes (2026-02-13):
  - Updated `Poll Watcher` page with integrated strike-list field workflow:
    - precinct-level supporter strike-list panel under report form
    - turnout-state quick actions (`Not Yet Voted`, `Voted`) per supporter
    - War Room-side one-tap contact outcomes (`Call Attempted`, `Reached`) per supporter
    - per-supporter optional note input applied to turnout/contact updates
  - Added strike-list controls optimized for field use:
    - mobile-friendly card rows with 44px+ action targets
    - supporter search (name/phone) and turnout-status filter
    - visible compliance notice on strike-list panel
    - success feedback banner after turnout/contact actions
  - Added web API client bindings for new strike-list endpoints:
    - `getPollWatcherStrikeList`
    - `updateStrikeListTurnout`
    - `createWarRoomContactAttempt`
  - Files:
    - `web/src/pages/admin/PollWatcherPage.tsx`
    - `web/src/lib/api.ts`
- 7.4 verification log (automated):
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 7.4 manual QA checklist (delegated to engineer):
  1. Login as `poll_watcher`, open `/admin/poll-watcher`, and select an assigned precinct.
  2. Confirm strike-list panel loads supporter cards for that precinct only.
  3. Use turnout buttons to toggle one supporter `Not Yet Voted -> Voted`; verify status badge updates.
  4. From War Room, log `Call Attempted` on a supporter and verify "last contact" summary appears/updates.
  5. Enter a note for a supporter before action and verify action still succeeds.
  6. Use strike-list search and turnout-status filter; verify list updates correctly.
  7. Confirm compliance note is visible in strike-list panel.
  8. Login as watcher assigned to different village/precinct and verify out-of-scope supporters are inaccessible.
- 7.5 implementation notes (2026-02-13):
  - Extended war-room backend payload with strike-list queue metrics:
    - village-level:
      - `not_yet_voted_count`
      - `outreach_attempted_count`
      - `outreach_reached_count`
    - island-wide stats:
      - `total_not_yet_voted`
      - `total_outreach_attempted`
      - `total_outreach_reached`
    - prioritized queue:
      - `not_yet_voted_queue` (top villages sorted by pending count + turnout)
  - Updated War Room UI with queue integration:
    - new top summary cards for remaining/attempted/reached outreach counts
    - new `Not Yet Voted Queue` sidebar panel showing prioritized villages and progress counters
    - existing call-priority and activity sections retained
  - Files:
    - `api/app/controllers/api/v1/war_room_controller.rb`
    - `api/test/controllers/api/v1/war_room_controller_test.rb`
    - `web/src/pages/admin/WarRoomPage.tsx`
- 7.5 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/war_room_controller_test.rb test/controllers/api/v1/poll_watcher_controller_test.rb` -> pass
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 7.5 manual QA checklist (delegated to engineer):
  1. As `poll_watcher`, mark supporters in one precinct as `not_yet_voted`, then `voted`.
  2. As war-room role (`campaign_admin`/`district_coordinator`/`village_chief`), open `/admin/war-room`.
  3. Confirm `Not Yet Voted Queue` panel appears and includes expected villages.
  4. Confirm queue ordering prioritizes villages with larger pending counts.
  5. Confirm top summary cards show non-zero values for remaining/attempted/reached after strike-list updates.
  6. Log contact attempts (`attempted` and `reached`) in Poll Watcher and confirm War Room counters update after refresh/realtime.
  7. Confirm village cards show updated per-village outreach counters (`not_yet_voted_count`, `outreach_attempted_count`, `outreach_reached_count`).
  8. Confirm no authorization regression: `block_leader` still cannot access war-room routes.
- 7.6 implementation notes (2026-02-13):
  - Expanded automated test coverage for strike-list scope/permissions:
    - `block_leader` denied from strike-list endpoints (`poll_watcher_access_required`)
    - `village_chief` allowed for assigned village strike-list access
    - `district_coordinator` blocked outside assigned district scope
  - Expanded model validation coverage:
    - invalid `SupporterContactAttempt` outcome rejected
    - invalid `SupporterContactAttempt` channel rejected
  - Added full manual simulation QA package:
    - `docs/testing/election-day-strike-list-simulation-checklist.md`
    - Includes preconditions, phased execution, audit/compliance checks, and sign-off template.
- 7.6 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/poll_watcher_controller_test.rb test/controllers/api/v1/war_room_controller_test.rb test/models/supporter_turnout_tracking_test.rb test/controllers/api/v1/supporters_controller_test.rb` -> pass
- 7.6 manual QA follow-up (delegated):
  - Run `docs/testing/election-day-strike-list-simulation-checklist.md`
  - Append pass/fail and defect notes to this tracker before final `7` item closure.
- 7.7 implementation notes (2026-02-13):
  - Added operator-facing election-day quick guide:
    - `docs/testing/poll-watcher-quick-guide.md`
  - Added pre-live readiness/go-no-go checklist:
    - `docs/testing/election-day-operator-readiness-checklist.md`
  - Coverage includes:
    - role roster confirmation
    - assignment scope verification
    - dry-run simulation linkage
    - escalation readiness and startup checks
    - final GO/NO-GO sign-off template
- 7.7 manual rollout checklist (delegated):
  1. Review `poll-watcher-quick-guide.md` with watchers/chiefs/coordinators.
  2. Complete `election-day-operator-readiness-checklist.md` in staging rehearsal.
  3. Record assignment verification and dry-run outcome in this tracker.
  4. Capture final GO/NO-GO decision with blockers and owners.
- Item 7 closure rule:
  - Mark parent Item `7` as `done` after delegated team posts:
    - completed strike-list simulation result
    - completed operator-readiness checklist
    - final GO decision (or NO-GO blockers) in this tracker.
- Item 7 handoff note:
  - Engineering implementation for `7.0` - `7.7` is complete.
  - Remaining action is delegated operations sign-off evidence capture (simulation + readiness + GO/NO-GO entry).

### 7B) Full-Voter Poll Watcher Overlay Workflow (Becky Clarification)
- Status: `in progress`
- Goal: move from supporter-only election-day strike lists to full GEC-voter turnout tracking with supporter overlay.
- Current branch implementation:
  - Full assigned GEC voter lists now power the poll watcher strike list.
  - A completed `gec_import` can be explicitly activated as the election-day voter list; when none is active, the app falls back to the latest active GEC list date.
  - Poll watcher scope now supports explicit precinct assignments, with assigned-village scope retained as the fallback for existing accounts.
  - Turnout updates are recorded on `gec_voters` and synced to linked supporters for legacy surfaces.
  - Supporter overlay metadata is returned for matched voters.
  - War room pending-supporter counts and detailed supporter queues are derived from linked supporters whose GEC voter turnout status is `not_yet_voted`.
  - Unmatched supporters are surfaced separately so operators know which records are excluded from the full-voter-derived queue.
- Remaining before marking done:
  - Clean rollout QA against realistic precinct data.
  - Confirm operations language and training materials with campaign leads.
  - Capture manual rehearsal evidence and GO/NO-GO sign-off.
- Scope:
  - Show the full assigned GEC voter list to poll watchers for turnout marking.
  - Record turnout against the voter universe, not just campaign supporters.
  - Overlay campaign supporter status on top of that turnout list.
  - Drive war room "who still needs a call?" queues from supporters who have not yet voted inside that full-voter turnout state.
- Acceptance criteria:
  - Poll watcher can mark turnout for any assigned GEC voter, regardless of supporter status.
  - Operators can identify the active election-day GEC list used for strike lists and war room derivation.
  - Poll watcher access can be constrained to explicit precinct assignments when assignments are loaded.
  - UI clearly distinguishes full-voter turnout tracking from supporter-only GOTV follow-up.
  - War room derives supporter call lists from the intersection of supporter status and `not_yet_voted` full-voter turnout.
  - Unmatched supporters are visible as a separate exception bucket, not silently mixed into or omitted from the derived queue.
  - Role/scope, audit, and manual rehearsal all pass for this full-voter workflow.

### 8) List UX Standardization (Search, Filters, Sorting)
- Status: `done`
- Goal: ensure all list-heavy pages support fast lookup and operations at campaign scale.
- Scope:
  - Define a shared list pattern for search + filters + sorting behavior.
  - Add search bars to key list pages that do not yet have search.
  - Add filter controls relevant to each page's domain (role, status, village, date, source, etc.).
  - Add sortable columns for table/list views, including click-to-sort column headers.
  - Normalize default sort order and clearly indicate active sort direction.
- Acceptance criteria:
  - Every major list page supports search and at least one filter.
  - Table columns that represent sortable values support click-to-sort.
  - Sort/filter/search state is reflected in URL params where practical.
  - UX remains mobile-friendly and accessible (touch targets + keyboard/focus support).
- Completed implementation coverage:
  - `Supporters`: URL-backed search/filter/sort + desktop column sort controls.
  - `Users`: URL-backed search/filter/sort + role filtering.
  - `Events`: URL-backed search/filter/sort + status/type filtering.
  - `Leaderboard`: URL-backed search/filter/sort by rank/signup/village/leader.
  - `Poll Watcher`: URL-backed precinct search/filter/sort (village/reporting/turnout).
  - `War Room`: URL-backed village search/filter/sort controls in turnout grid.

### 9) Reporting Foundation (Requirements + First Report Set)
- Status: `todo`
- Goal: define and implement high-value operational reports for leadership and field teams.
- Scope:
  - Identify first reporting set with stakeholders (campaign admin + coordinators).
  - Define report dimensions (date range, village, precinct, role, source, turnout status).
  - Define output modes (on-screen summary cards/tables + CSV export).
  - Implement at least one end-to-end report module with filters and export.
  - Add report access control and audit trail for report generation/export actions (if needed).
- Acceptance criteria:
  - Report requirements are documented and approved.
  - At least one production-ready report is shipped with filters + export.
  - Report outputs are validated against known sample data.
  - RBAC rules for report visibility/access are enforced.

### 10) UX Motion and Transition Polish
- Status: `todo`
- Goal: improve perceived quality by smoothing abrupt UI state changes (sorting, filtering, section expand/collapse, data refresh states).
- Scope:
  - Define a small motion standard (durations/easing/reduced-motion behavior).
  - Apply smooth transitions to list re-sorts/filter refreshes and key card/table state changes.
  - Improve loading/refresh micro-interactions to avoid "snap" behavior.
  - Ensure motion remains subtle, fast, and accessible.
- Acceptance criteria:
  - High-traffic pages (supporters, users, events, dashboard cards) no longer feel abrupt during sort/filter changes.
  - Motion follows one consistent timing standard.
  - Reduced-motion preference is respected.
  - QA sign-off confirms improved UX smoothness without usability regressions.

### 11) Scale Hardening for 30,000+ Supporters/Voters (Do It Right)
- Status: `in_progress`
- Goal: make core pages and APIs production-ready for high-volume campaign data (30k+ supporter records) without band-aid fixes.
- Scope:
  - Define explicit performance budgets (p95 API response, list render time, query count limits).
  - Standardize server-side pagination/filter/sort across all list endpoints (no large client-side list operations for high-volume data).
  - Add/verify DB indexes for dominant query paths (supporters list filters, search, sort, war-room and poll-watcher reads).
  - Introduce selective caching for high-read dashboards/aggregates with safe invalidation strategy.
  - Add frontend strategy for large lists (incremental fetch, stable URL state, and where needed windowing/virtualization).
  - Add repeatable load/performance tests and capture baseline metrics before/after each optimization batch.
  - Add observability for key endpoints (request time, query count, error rate) in non-prod and production.
- Acceptance criteria:
  - Supporters list interactions (search/filter/sort/page) remain responsive at 30k+ records.
  - Target endpoints meet agreed p95 latency budgets under representative load.
  - No N+1 regressions on high-traffic endpoints (validated by tests/profiling).
  - Performance test suite and baseline report are checked in and runnable by the team.
  - Operational runbook exists for performance troubleshooting and scaling decisions.
- Implementation task breakdown:
  - **11.1 Synthetic data generation + stress dataset seeding**
    - Status: `done` (2026-02-13)
    - Add repeatable non-production seed/generator for high-volume supporter datasets (5k, 10k, 30k).
    - Ensure realistic distributions (village/precinct/source/status/date spread) for meaningful tests.
    - Add safe guardrails so this flow cannot run accidentally in production.
    - Acceptance: team can generate/re-generate stress datasets on demand with deterministic commands.
  - **11.2 Baseline performance benchmark pass**
    - Status: `in_progress`
    - Benchmark key endpoints and UI flows against stress datasets (supporters list, dashboard, war room, poll watcher).
    - Capture p50/p95 timings, query counts, and UX interaction latency.
    - Acceptance: baseline report documented and linked in repo for comparison after optimizations.
  - **11.3 Server/query optimization batch**
    - Status: `in_progress`
    - Add/adjust indexes and query plans from benchmark findings.
    - Standardize server-side sort/filter/page behavior across list endpoints.
    - Acceptance: measurable improvements against baseline on top endpoints.
  - **11.4 Frontend high-volume rendering strategy**
    - Status: `in_progress`
    - Ensure list pages avoid expensive client-side operations for large datasets.
    - Add virtualization/windowing where needed for dense tables/lists.
    - Acceptance: interaction responsiveness remains stable at high data volume.
  - **11.5 Observability + regression guardrails**
    - Status: `in_progress`
    - Add lightweight endpoint timing/query-count visibility and periodic performance checks.
    - Add CI or scheduled checks for critical performance regressions.
    - Acceptance: regressions are detected early with clear alerting/reporting path.
- 11.1 implementation notes:
  - Added rake task: `api/lib/tasks/synthetic_data.rake`
  - Task: `rails "data:seed_synthetic_supporters[SIZE]"`
  - Supported preset sizes: `5000`, `10000`, `30000`
  - Guardrails:
    - Blocked in production environment
    - Deterministic generation via `SEED` env
    - Optional clean-up of prior synthetic rows via `RESET=true` (deletes `leader_code LIKE 'SYNTH-%'`)
    - Optional validation run via `DRY_RUN=true` (no DB writes)
- 11.1 command reference:
  - Dry run (no inserts): `DRY_RUN=true bundle exec rails "data:seed_synthetic_supporters[5000]"`
  - Seed 5k: `bundle exec rails "data:seed_synthetic_supporters[5000]"`
  - Seed 10k (reset previous synthetic): `RESET=true bundle exec rails "data:seed_synthetic_supporters[10000]"`
  - Seed 30k (deterministic): `SEED=20260213 bundle exec rails "data:seed_synthetic_supporters[30000]"`
- 11.1 verification log:
  - `DRY_RUN=true bundle exec rails "data:seed_synthetic_supporters[5000]"` -> pass (distribution output generated)
- 11.2 implementation notes:
  - Added benchmark task: `api/lib/tasks/performance_baseline.rake`
  - Task: `rails "performance:capture_baseline[DATASET_SIZE]"`
  - Captures per-scenario timing (`p50/p95/avg/min/max`) and SQL query counts.
  - Scenarios covered: supporters index (default + filtered), dashboard payload, war room payload, poll watcher payload.
  - Raw reports generated:
    - `docs/performance/baseline-20260213-165539.json` (5k)
    - `docs/performance/baseline-20260213-165549.json` (10k)
    - `docs/performance/baseline-20260213-165604.json` (30k)
    - `docs/performance/baseline-latest.json`
  - Summary report:
    - `docs/performance/baseline-report-2026-02-13.md`
- 11.2 verification log (automated):
  - `RESET=true bundle exec rails "data:seed_synthetic_supporters[5000]"` -> pass
  - `bundle exec rails "performance:capture_baseline[5000]"` -> pass
  - `RESET=true bundle exec rails "data:seed_synthetic_supporters[10000]"` -> pass
  - `bundle exec rails "performance:capture_baseline[10000]"` -> pass
  - `RESET=true bundle exec rails "data:seed_synthetic_supporters[30000]"` -> pass
  - `bundle exec rails "performance:capture_baseline[30000]"` -> pass
- 11.2 manual QA follow-up (delegated):
  - Complete UI interaction latency capture checklist in `docs/performance/baseline-report-2026-02-13.md`
  - Append measured UI timings to the same report before closing 11.2 as `done`
- 11.3 first optimization pass (2026-02-13):
  - Refactored `war_room` aggregation to remove per-village N+1 count/sum queries.
  - Added supporter indexes:
    - `supporters(status, village_id)`
    - `supporters(status, village_id, motorcade_available)`
  - Re-ran 30k benchmark:
    - Before: `docs/performance/baseline-20260213-165604.json`
    - After: `docs/performance/baseline-20260213-170308.json`
  - Measured improvement (`war_room_index_payload`):
    - SQL query avg: `42.0` -> `5.0`
    - p50 latency: `44.52ms` -> `7.88ms`
    - p95 latency: `54.03ms` -> `8.84ms`
- 11.3 second optimization pass (2026-02-13):
  - Refactored dashboard aggregation to reuse preloaded village totals and avoid extra aggregate count/sum queries.
  - Added supporter list indexes:
    - `supporters(created_at)`
    - `supporters(village_id, created_at)`
    - `supporters(precinct_id, created_at)`
  - Re-ran 30k benchmark:
    - Before: `docs/performance/baseline-20260213-170308.json`
    - After: `docs/performance/baseline-20260213-170506.json`
  - Measured improvement:
    - `supporters_index_default` p50: `10.69ms` -> `5.47ms`
    - `dashboard_show_payload` p50: `18.62ms` -> `12.59ms`
    - `war_room_index_payload` p50: `7.88ms` -> `4.05ms`
  - Follow-up note:
    - `supporters_index_filtered_search` p95 remains volatile and should be addressed in next 11.3 pass (search-specific index strategy).
- 11.3 third optimization pass (2026-02-13):
  - Added search-specific trigram indexes:
    - `GIN (LOWER(supporters.print_name) gin_trgm_ops)`
    - `GIN (supporters.contact_number gin_trgm_ops)`
  - Updated supporter search logic to include digit-normalized phone matching.
  - Re-ran 30k benchmark:
    - Before: `docs/performance/baseline-20260213-170506.json`
    - After: `docs/performance/baseline-20260213-170652.json`
  - Measured search-path improvement:
    - `supporters_index_filtered_search` p50: `11.34ms` -> `9.28ms`
    - `supporters_index_filtered_search` p95: `42.44ms` -> `14.84ms`
  - Note:
    - non-search scenarios show expected run-to-run variance in development; primary validated gain is supporter search path.
- 11.3 election-day load validation pass (2026-02-13):
  - Added synthetic poll report generator task:
    - `rails "data:seed_synthetic_poll_reports[8]"` (with `RESET_TODAY=true` support)
  - Added index:
    - `poll_reports(reported_at)`
  - Seeded load:
    - `59 precincts * 8 reports = 472` poll reports for today
  - Post-load benchmark (first capture):
    - `docs/performance/baseline-20260213-170925.json`
    - `war_room_index_payload`: p50 `12.31ms`, p95 `25.26ms`, avg SQL `7.0`
    - `poll_watcher_index_payload`: p50 `6.32ms`, p95 `9.32ms`, avg SQL `3.0`
  - Repeat-run note:
    - subsequent dev captures showed significant wall-clock variance with stable SQL counts; final threshold sign-off should be done in isolated/staging environment.
- 11.3 staging sign-off package (2026-02-13):
  - Added one-command staging benchmark script:
    - `api/bin/performance_staging_run`
  - Added operator checklist:
    - `docs/performance/staging-benchmark-checklist.md`
  - Closure rule:
    - mark `11.3` as `done` after one clean staging run meets query-shape and latency consistency checks.
- 11.4 first frontend performance pass (2026-02-13):
  - Applied high-volume-focused improvements to `Supporters` list page:
    - debounced server-backed search input (`250ms`) to reduce query thrash on fast typing
    - preserved previous list data during refetch to avoid UI snap/flicker
    - adaptive row animation behavior: disables expensive row layout transitions for large datasets (`>= 5000`)
  - Files:
    - `web/src/hooks/useDebouncedValue.ts`
    - `web/src/pages/admin/SupportersPage.tsx`
  - Result:
    - smoother search/filter/sort interactions under high data volume with less render churn.
- 11.4 second frontend performance pass (2026-02-13):
  - Added server-backed page-size control on `Supporters` (`25/50/100/200` rows per page).
  - Added adjacent-page query prefetch for smoother next-page navigation under heavy datasets.
  - Persisted `per_page` in URL state for stable refresh/share behavior.
  - Result:
    - improved perceived responsiveness for high-volume browsing and pagination.
- 11.4 third frontend performance pass (2026-02-13):
  - Added progressive chunked row rendering for high-volume `Supporters` views (`>=5000` total rows + `per_page >= 100`).
  - Initial paint now renders a capped row subset, then incrementally hydrates remaining rows in short batches to reduce long main-thread paint spikes.
  - Added inline render-progress feedback (`Rendering X / Y rows...`) during chunk hydration for operator clarity on dense pages.
  - File:
    - `web/src/pages/admin/SupportersPage.tsx`
  - Verification:
    - `npm run lint` (web) -> pass
    - `npm run build` (web) -> pass
  - Result:
    - smoother first-paint and scroll responsiveness on 100-200 row pages under synthetic 30k supporter volume.
- 11.4 manual QA run (delegated to engineer):
  1. Prepare high-volume dataset:
     - Run `RESET=true bundle exec rails "data:seed_synthetic_supporters[30000]"` from `api/`.
     - Confirm app boots with seeded data and admin login works.
  2. Verify baseline browsing on `Supporters`:
     - Open `/admin/supporters`.
     - Set rows-per-page to `200/page`.
     - Confirm first render is responsive and page does not appear frozen during initial table paint.
  3. Verify progressive rendering behavior:
     - With `200/page` active, confirm temporary helper text appears (`Rendering X / Y rows...`) and disappears once row hydration completes.
     - Confirm no duplicate or missing rows after hydration settles.
  4. Verify high-volume interaction responsiveness:
     - Scroll through the table immediately after page load.
     - Apply `Village`, `Precinct`, and `Source` filters in sequence.
     - Change sort field/direction twice.
     - Expected: no major UI lockups; interactions remain usable while data refreshes.
  5. Verify search debounce and refetch stability:
     - Type a 10+ character search string quickly in the search input.
     - Expected: requests are not fired on every keystroke and list does not hard-flicker to empty between refreshes.
  6. Verify pagination smoothness:
     - Navigate page `1 -> 2 -> 3 -> 2`.
     - Expected: next-page transitions feel smoother (prefetch benefit), with no broken loading state.
  7. Verify URL/state persistence:
     - Keep non-default filters/sort/page size, refresh browser.
     - Expected: `per_page` and other URL-backed controls restore correctly.
  8. Capture QA evidence:
     - Record browser, machine profile, dataset size, and any visible lag points.
     - Append findings to this section with `pass/fail` per step and short notes.
- 11.4 closure criteria:
  - Mark `11.4` as `done` once delegated QA confirms steps 2-7 pass on 30k dataset with no blocking UX regressions.
- 11.5 implementation notes (2026-02-13):
  - Added request-level API performance instrumentation:
    - `api/app/services/request_performance_observer.rb`
    - `api/app/controllers/application_controller.rb` (`around_action :track_request_performance`)
  - Added per-request structured performance logging payload:
    - event: `api_request_performance`
    - fields: `method`, `path`, `status`, `duration_ms`, `sql_query_count`, `request_id`
  - Added response headers for quick endpoint inspection:
    - `X-Request-Duration-Ms`
    - `X-SQL-Query-Count`
  - Behavior:
    - enabled by default in non-test, non-production environments
    - production-gated by `REQUEST_PERF_OBSERVABILITY=true`
    - slow-request warning threshold configurable via `REQUEST_SLOW_THRESHOLD_MS` (default `500`)
  - Added periodic regression guardrail task:
    - `api/lib/tasks/performance_regression.rake`
    - `rails "performance:regression_check"` validates p95 + avg SQL guardrails against `docs/performance/baseline-latest.json`
  - Added convenience runner:
    - `api/bin/performance_regression_check` (capture baseline + run guardrail check in sequence)
  - Env template updates:
    - `api/.env.example` now includes `REQUEST_PERF_OBSERVABILITY` and `REQUEST_SLOW_THRESHOLD_MS`
- 11.5 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/supporters_controller_test.rb` -> pass
  - `bundle exec rails "performance:regression_check"` -> pass
- 11.5 manual QA run (delegated to engineer):
  1. Local visibility check:
     - Ensure API is running in development.
     - Call `GET /api/v1/supporters` as an authorized user.
     - Confirm response contains `X-Request-Duration-Ms` and `X-SQL-Query-Count`.
  2. Log verification:
     - Inspect API logs for `event:"api_request_performance"` entries.
     - Confirm fields include path, status, request_id, duration, and query count.
  3. Slow-path threshold verification:
     - Temporarily set `REQUEST_SLOW_THRESHOLD_MS=1` in local env and restart API.
     - Trigger one endpoint request and confirm warning-level log behavior.
  4. Regression guardrail verification:
     - Run `api/bin/performance_regression_check` (or run `performance:capture_baseline` + `performance:regression_check` manually).
     - Confirm the command exits cleanly on pass and produces actionable output on failure.
  5. Staging production-gate verification:
     - With `REQUEST_PERF_OBSERVABILITY=false`, confirm no perf headers/log entries are emitted.
     - With `REQUEST_PERF_OBSERVABILITY=true`, confirm headers/log entries appear for API requests.
- 11.5 closure criteria:
  - Mark `11.5` as `done` after delegated QA confirms instrumentation visibility + guardrail task behavior in local/staging and logs results in this tracker.

### 12) Operations Configurability (Quotas + Precinct Metadata)
- Status: `in_progress`
- Goal: allow campaign head admins to safely adjust operational numbers/metadata that may change mid-campaign without engineering intervention.
- Scope:
  - Add admin-only quota management (per village target updates) in app.
  - Add guarded precinct metadata management (number/alpha range/polling site, activate/deactivate; avoid destructive deletes).
  - Keep village structural changes tightly restricted (minimal metadata edits only, if enabled).
  - Add audit history for all config changes with actor + field-level `from` -> `to` diffs.
  - Add validation and safe-guards to prevent breaking existing supporter mappings.
- Acceptance criteria:
  - Head admins can update quota targets from the UI and changes are reflected immediately in dashboard/village views.
  - Precinct metadata updates are possible without orphaning supporter records.
  - Sensitive operations are role-gated and fully audited.
  - Manual QA confirms change flow is understandable for non-technical campaign operators.
- Implementation task breakdown:
  - **12.1 Quota admin UI + API**
    - Status: `done` (2026-02-13)
    - Add endpoints/UI for listing and updating village quota targets.
    - Add optimistic UI feedback and last-updated metadata.
    - Acceptance: quota edits succeed with role checks and update downstream metrics.
  - **12.2 Precinct metadata management**
    - Status: `done` (2026-02-13)
    - Add endpoints/UI for updating precinct number/alpha range/polling site and active state.
    - Block destructive operations that would break linked supporters.
    - Acceptance: admin can safely maintain precinct metadata in production.
  - **12.3 Audit + guardrails**
    - Status: `done` (2026-02-13)
    - Ensure all config edits emit auditable records.
    - Add confirmation prompts and input validation for high-impact changes.
    - Acceptance: every config change is traceable and reversible through controlled edits.
  - **12.4 Registered voter reference-data updates (village + precinct)**
    - Status: `done` (2026-02-13)
    - Add controlled admin/coordinator editing for `registered_voters` at village and precinct level.
    - Keep strict guardrails: positive integer validation, role-gated access, and explicit save confirmation.
    - Record full audit trail (`from` -> `to`, actor, timestamp, metadata source note when provided).
    - Surface "last updated" context in admin UI so operators know data freshness.
    - Acceptance: authorized users can update voter counts safely, changes reflect in dashboard/ops views, and every change is fully auditable.
- 12.1 implementation notes:
  - API endpoints added:
    - `GET /api/v1/quotas` (list village quotas for active campaign)
    - `PATCH /api/v1/quotas/:village_id` (upsert/update target count)
  - Frontend admin page added:
    - `GET /admin/quotas` (search + inline target edits + save)
  - Dashboard quick-link added for authorized roles.
  - Audit log entries now record quota target changes with field-level diffs.
- 12.1 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/quotas_controller_test.rb` -> pass
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 12.1 manual QA checklist (for delegated engineer):
  1. Login as `campaign_admin` and open `/admin/quotas`.
  2. Confirm village list loads with current quota values.
  3. Change one village quota to a new positive value; click Save.
  4. Confirm success notice appears and value persists on refresh.
  5. Confirm dashboard village card and village detail percent/target reflect updated value.
  6. Enter `0` or negative number and verify Save is blocked/rejected.
  7. Login as non-coordinator role (`block_leader`) and verify route is unauthorized.
  8. (Optional DB check) confirm an `audit_logs` row exists for `Quota` update with `target_count from -> to`.
- 12.2 implementation notes:
  - API endpoints added:
    - `GET /api/v1/precincts` (search/filter/list with linked supporter counts)
    - `PATCH /api/v1/precincts/:id` (update number/alpha range/polling site/active)
  - Frontend admin page added:
    - `GET /admin/precincts` (search/filter + inline edits + save)
  - Dashboard quick-link added for authorized roles.
  - Guardrail implemented:
    - Deactivation is blocked when supporters are assigned to that precinct (`precinct_in_use`).
  - Audit log entries now record precinct metadata changes with field-level diffs.
- 12.2 verification log (automated):
  - `bundle exec rails db:migrate` -> pass (`AddActiveToPrecincts`)
  - `bundle exec rails test test/controllers/api/v1/precincts_controller_test.rb test/controllers/api/v1/quotas_controller_test.rb` -> pass
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 12.2 manual QA checklist (for delegated engineer):
  1. Login as `campaign_admin` and open `/admin/precincts`.
  2. Search/filter precincts and confirm list updates correctly.
  3. Edit `alpha_range` and `polling_site` for one precinct; click Save.
  4. Refresh and confirm values persist.
  5. Confirm village detail and poll watcher views reflect updated precinct metadata.
  6. Attempt to clear precinct number and verify save is blocked/rejected.
  7. For precinct with assigned supporters, attempt to set inactive and verify warning + rejection.
  8. For precinct with no supporters assigned, set inactive and verify save succeeds.
  9. Login as non-coordinator role (`block_leader`) and verify route is unauthorized.
  10. (Optional DB check) confirm an `audit_logs` row exists for `Precinct` update with field-level diffs.
- 12.4 implementation notes:
  - API updates:
    - `PATCH /api/v1/villages/:id` now supports controlled `registered_voters` updates (coordinator-or-above).
    - `PATCH /api/v1/precincts/:id` now supports `registered_voters` updates.
  - Guardrails:
    - positive integer validation for village/precinct registered voters.
    - role-gated access (coordinator-or-above).
    - explicit confirmation prompts in admin UI before voter-count updates.
  - Audit:
    - village and precinct voter-count updates emit `AuditLog` entries with field-level `from` -> `to` diffs.
  - Frontend:
    - `Quota Settings` now supports editing and saving village `registered_voters`.
    - `Precinct Settings` now supports editing and saving precinct `registered_voters`.
- 12.4 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/villages_controller_test.rb test/controllers/api/v1/precincts_controller_test.rb` -> pass
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 12.4 manual QA checklist (for delegated engineer):
  1. Login as `campaign_admin` and open `/admin/quotas`.
  2. Update `registered_voters` for one village and confirm confirmation prompt appears.
  3. Save and refresh; confirm updated value persists.
  4. Confirm dashboard totals and village detail show updated village voter count.
  5. Open `/admin/precincts` and update `registered_voters` for one precinct.
  6. Confirm confirmation prompt appears and save succeeds.
  7. Refresh and confirm updated precinct voter count persists.
  8. Try setting village/precinct voter count to `0` and verify update is rejected.
  9. Login as `block_leader` and verify village/precinct update routes are unauthorized.
  10. (Optional DB check) confirm `AuditLog` rows exist for village/precinct voter-count updates.
- 12.3 implementation notes:
  - Added optional `change_note` support on config update APIs:
    - `PATCH /api/v1/quotas/:village_id`
    - `PATCH /api/v1/villages/:id`
    - `PATCH /api/v1/precincts/:id`
  - Audit metadata now consistently includes:
    - `resource`
    - scope IDs (e.g., `village_id` for precinct/quota updates)
    - optional `change_note` when provided
  - Added explicit confirmation prompts for high-impact UI actions:
    - quota target updates
    - village registered-voter updates
    - precinct deactivation
    - precinct registered-voter updates
  - Added validation guardrails for registered voter counts (> 0) on village/precinct updates.
- 12.3 verification log (automated):
  - `bundle exec rails test test/controllers/api/v1/quotas_controller_test.rb test/controllers/api/v1/villages_controller_test.rb test/controllers/api/v1/precincts_controller_test.rb` -> pass
  - `npm run lint` (web) -> pass
  - `npm run build` (web) -> pass
- 12.3 manual QA checklist (for delegated engineer):
  1. In `/admin/quotas`, enter a quota change with a change note and confirm prompt appears.
  2. Save and verify success notice appears.
  3. In `/admin/quotas`, update village registered voters with a change note and confirm prompt appears.
  4. In `/admin/precincts`, update precinct registered voters and confirm prompt appears.
  5. In `/admin/precincts`, deactivate a no-supporter precinct and confirm deactivation prompt appears.
  6. Attempt invalid voter count (`0`) for village/precinct and verify rejection.
  7. (Optional DB check) confirm `audit_logs.metadata.change_note` persists when note is provided.

---

## Later (Phase 2+)

### Product Enhancements
- Status: `todo`
- Structured address fields (street/city/zip shape aligned to campaign ops).
- Optional supporter confirmation email flow.
- Phone input masking for friendlier entry format.

### Election-Day Scale Enhancements
- Status: `todo`
- War room performance/load hardening.
- Poll watcher offline reliability and sync strategy refinement.
- Supporter-level strike-list reliability at scale (high-frequency updates + conflict handling).

---

## Decision Log (Quick Notes)

- 2026-02-13: Adopt show-first supporter detail UX; editing requires explicit action.
- 2026-02-13: Track execution in this document as the operational source of truth.
- 2026-02-13: Supporter edit permissions enforced for admin/coordinator only; other roles read-only.
- 2026-02-13: Audit log payload upgraded to field-level `from` -> `to` diffs with actor role and action label.
