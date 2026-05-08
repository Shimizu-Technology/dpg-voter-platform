# Campaign Tracker Issue Audit and Test Plan

Date: 2026-02-13  
Prepared by: AI code review pass

## Live Validation Results (2026-02-13)

Status key:
- **Confirmed**: reproduced live and/or directly proven from runtime + source
- **Partially Confirmed**: strong source proof, but full runtime scenario requires auth/role setup or external env access
- **Not Validated**: could not be validated in this pass

### Critical
- **C1 — Confirmed**
  - Live test: unauthenticated websocket upgrade to `http://127.0.0.1:3000/cable` returned `101 Switching Protocols` and ActionCable `{"type":"welcome"}` without credentials.
  - Runtime logs show subscription/streaming for `CampaignChannel`.
- **C2 — Confirmed**
  - Repo has no root `.github/workflows/` directory; workflow exists at `api/.github/workflows/ci.yml`.
- **C3 — Confirmed**
  - `web/.netlify/netlify.toml` contains absolute machine-specific paths (`/Users/jerry/...`), not portable for shared CI/deploy config.

### High
- **H1 — Partially Confirmed**
  - Source-level proof: JWT decode uses `verify_iss: false` and `verify_aud: false`.
  - Full forged-token runtime test requires controlled signed token harness.
- **H2 — Partially Confirmed**
  - Source-level proof: unknown Clerk subject auto-creates app user with `block_leader` role.
  - Full runtime validation requires valid external Clerk login for a non-preapproved user.
- **H3 — Confirmed**
  - Source-level proof: `SmsController` only enforces `authenticate_request`; no `require_admin!` or coordinator guard.
- **H4 — Confirmed (updated detail)**
  - Live test: API responds at `http://127.0.0.1:3000/api/v1/stats` with `200`.
  - Live test: frontend dev proxy (`http://localhost:5175/api/v1/stats`) returns `500` and Vite logs `ECONNREFUSED`.
  - Root cause observed: `web/vite.config.ts` proxies `/api` to `3001` while Rails currently runs on `3000`.
- **H5 — Confirmed**
  - `git ls-files web/.env.production` shows file is tracked.

### Medium
- **M1 — Confirmed**
  - Source + lint proof: stale closure in `checkForDuplicate` (`useCallback` deps missing `villages`), also flagged by ESLint `react-hooks/exhaustive-deps`.
- **M2 — Confirmed**
  - Live test: POST to `/api/v1/supporters` logged raw parameters including `print_name` and `contact_number` in Rails logs.
- **M3 — Partially Confirmed**
  - Source-level proof: OCR service logs extracted name/village.
  - Not executed live due no OCR image API run in this validation pass.
- **M4 — Partially Confirmed**
  - Source-level proof: poll watcher report endpoint sets `report.user` but does not enforce precinct assignment authorization.
  - Full runtime validation requires role/assignment fixtures + authenticated users.
- **M5 — Partially Confirmed**
  - Source-level proof: `per_page` in supporters index is not bounded.
  - Runtime stress test blocked by auth requirement for index/export endpoints in this pass.
- **M6 — Partially Confirmed**
  - Source-level proof: synchronous loops with `sleep(0.1)` in request lifecycle for event and SMS notification paths.
  - Full runtime timing test requires authenticated trigger and larger dataset.
- **M7 — Partially Confirmed**
  - Source-level proof: realtime toast dereferences `event.data.*` without guards.
  - Malformed event injection not executed in browser during this pass.
- **M8 — Partially Confirmed**
  - Source-level proof: `setTimeout` in toast hook has no unmount cleanup.
  - React warning reproduction not executed in browser during this pass.

### Low / Quality
- **L1 — Confirmed**
  - Live test: `npm run lint` reports many `no-explicit-any` and unused-symbol errors/warnings (43 errors, 1 warning in prior run).
- **L2 — Confirmed**
  - Source-level proof: mixed API usage patterns (direct axios call in landing page vs helper methods).

### Additional live note (deployment)
- The checked `VITE_API_URL` target in `web/.env.production` (`https://campaign-tracker-api-5v6n.onrender.com`) returned `404` for `/` and `/api/v1/stats` during this pass. This may indicate a wrong URL, sleeping/undeployed service variant, or route mismatch and should be verified in Render dashboard.

## Fix Progress (in progress)

### Fixed in code
- **C1** ActionCable now requires authenticated user context; unauthenticated sockets are disconnected.
- **C2** Added root workflow file at `.github/workflows/ci.yml` with monorepo-aware working directories.
- **C3** Replaced non-portable Netlify absolute paths with relative config.
- **H1** JWT issuer verification enabled; optional audience verification supported via `CLERK_JWT_AUDIENCE`.
- **H2** Auto-provisioning disabled by default (`AUTO_PROVISION_USERS=false` unless explicitly enabled).
- **H3** SMS send/blast/event-notify now require coordinator-or-above.
- **H4** Local API/proxy defaults aligned to Rails on `3000`.
- **H5** Added ignore rule for `web/.env.production` and `.env.example` files for both apps.
- **M1** StaffEntry duplicate check callback dependency fixed.
- **M2** Added campaign PII fields to Rails parameter filtering.
- **M3** Redacted OCR extraction log message.
- **M5** Added supporters pagination cap and export size guard.
- **M6** Moved heavy SMS/event send loops into background jobs.
- **M4 (partial)** Poll watcher now enforces precinct scope by role/assignment for report/history and filtered index data.
- **M10/M11 from backend review** Added supporter validations for precinct/block-village consistency.
- **L1** Frontend lint baseline cleaned up (no current ESLint errors).
- **Test coverage start** Added model tests for supporter village/precinct/block integrity checks.
- **Security request tests** Added integration tests for SMS role gates, poll watcher precinct scoping, and supporters auth/pagination caps.

### Remaining to finish
- Full automated tests for new auth/role/job behaviors.
- Poll watcher assignment policy refinement if campaign wants stricter district/block logic.
- Broader frontend type-safety and lint debt cleanup (`any` usage across multiple pages).
- Mobile touch target pass against 44px design standard.

## Decision Recommendations (Open Questions)

### 1) Should all authenticated roles be allowed to send SMS blasts?

Recommendation: **No**. Restrict high-impact messaging actions.

- `sms/blast` and `sms/event_notify`: allow `admin` and `coordinator` only
- `sms/send` (single test SMS): allow `admin`/`coordinator`, or keep for all staff with strict rate limits and audit logs
- Keep read-only SMS status available to all authenticated users if needed

Why:
- Blast messaging has cost + reputational risk (accidental spam, abuse, wrong audience)
- Least-privilege is safer for campaign operations
- Easier to audit and train staff around clear permissions

### 2) Deployed on Netlify + Render; uncertain about `/api/v1` routing

Recommendation: **Treat as high-risk until verified in production**.

- Frontend currently calls relative `'/api/v1'`
- If Netlify does not proxy `/api/*` to Render API, requests can fail or hit wrong origin
- Ensure one canonical setup:
  - Option A: Use `VITE_API_URL` absolute URL everywhere
  - Option B: Keep relative `/api` but add explicit Netlify redirect/proxy rules

### 3) Should ActionCable remain unauthenticated?

Recommendation: **No for production**.

- Require auth on websocket connection (same trust model as API routes)
- Limit stream access by role/scope if needed
- Move production cable adapter to Redis for multi-process reliability

Why:
- Current stream exposes campaign activity updates to any client that can connect

---

## Prioritized Issue List with Test-First Validation

Use this section to confirm each issue **before fixing** and then verify after the fix.

### Critical

#### C1. ActionCable connection/stream is unauthenticated
- Area: `api/app/channels/application_cable/connection.rb`, `api/app/channels/campaign_channel.rb`
- Risk: Unauthorized users can subscribe to real-time campaign updates
- Confirm before fix:
  1. Open browser console in a non-authenticated context
  2. Create ActionCable consumer to `/cable` and subscribe to `CampaignChannel`
  3. Trigger a known event (new supporter, poll report, check-in) from authenticated app flow
  4. Verify event is received by unauthenticated subscriber
- Expected current behavior: Subscription succeeds and events are received
- Verify after fix:
  1. Repeat with no token or invalid token
  2. Confirm connection/subscription is rejected
  3. Repeat with valid token; confirm subscription works

#### C2. CI workflow path likely wrong for GitHub Actions
- Area: `api/.github/workflows/ci.yml`
- Risk: CI may not run at all
- Confirm before fix:
  1. Open GitHub Actions tab
  2. Push a trivial branch update
  3. Check if workflow triggers
- Expected current behavior: No workflow trigger from repo root unless workflow is moved
- Verify after fix:
  1. Move workflow to repo root `.github/workflows/`
  2. Push branch update
  3. Confirm jobs run and report status

#### C3. Netlify config contains machine-specific absolute paths
- Area: `web/.netlify/netlify.toml`
- Risk: Build/deploy misconfiguration and brittle deployments
- Confirm before fix:
  1. Compare Netlify UI build logs against repository config
  2. Validate whether config in repo is ignored or causing drift/confusion
- Expected current behavior: Config is not portable; path values do not exist in CI environment
- Verify after fix:
  1. Replace with relative paths (or root `netlify.toml` pattern)
  2. Trigger deploy
  3. Confirm clean build and consistent behavior

---

### High

#### H1. JWT decode disables issuer/audience verification
- Area: `api/app/controllers/concerns/authenticatable.rb`
- Risk: Token validation is weaker than intended
- Confirm before fix:
  1. Generate validly signed test JWT with mismatched `iss`/`aud` (test harness)
  2. Call authenticated endpoint with token
- Expected current behavior: Token may still be accepted
- Verify after fix:
  1. Enable `verify_iss`/`verify_aud` with expected values
  2. Re-run test; mismatched token rejected, valid token accepted

#### H2. Auto-creating users from token subject
- Area: `api/app/controllers/concerns/authenticatable.rb`
- Risk: Unknown users can become `block_leader` automatically
- Confirm before fix:
  1. Authenticate using a valid Clerk account not pre-approved in app
  2. Hit protected endpoint
  3. Inspect DB for new `users` record
- Expected current behavior: User record auto-created with default role
- Verify after fix:
  1. Enforce allowlist/invite/approval flow
  2. Unknown user receives `403` (or onboarding blocked)
  3. No auto-provisioned user row unless explicitly intended

#### H3. SMS blast/event endpoints lack role authorization
- Area: `api/app/controllers/api/v1/sms_controller.rb`
- Risk: Any authenticated user can trigger bulk sends
- Confirm before fix:
  1. Login as lowest staff role
  2. POST `/api/v1/sms/blast` with `dry_run=true`, then non-dry-run in test environment
  3. POST `/api/v1/sms/event_notify`
- Expected current behavior: Requests succeed
- Verify after fix:
  1. Add role guard (`require_coordinator_or_above!` or stricter)
  2. Lowest role gets `403`
  3. Allowed roles succeed

#### H4. Local realtime default points to wrong API port
- Area: `web/src/lib/cable.ts`, `web/vite.config.ts`
- Risk: Websocket fails locally when `VITE_API_URL` is not set
- Confirm before fix:
  1. Run API on `3001`, web on `5175`
  2. Leave `VITE_API_URL` unset
  3. Open War Room and check websocket connection
- Expected current behavior: Connection attempts `ws://localhost:3000/cable` and fails
- Verify after fix:
  1. Align fallback with API port or single source of truth
  2. Confirm successful websocket connection and event receipt

#### H5. Tracked environment file in repo
- Area: `web/.env.production` (tracked)
- Risk: Configuration leakage and environment drift
- Confirm before fix:
  1. `git ls-files web/.env.production`
  2. Confirm file is versioned
- Expected current behavior: file appears as tracked
- Verify after fix:
  1. Remove tracked env file from git history/index strategy as agreed
  2. Use Netlify/Render environment variables
  3. Confirm app works with CI/deploy env vars only

---

### Medium

#### M1. StaffEntry duplicate warning uses stale `villages` closure
- Area: `web/src/pages/admin/StaffEntryPage.tsx`
- Risk: Wrong duplicate-warning village name; potential false UX confidence
- Confirm before fix:
  1. Load villages
  2. Trigger duplicate warning
  3. Check warning village label
- Expected current behavior: Often shows fallback `this village` incorrectly
- Verify after fix:
  1. Add `villages` dependency to callback (or refactor)
  2. Warning always shows correct village name

#### M2. Incomplete parameter filtering for PII
- Area: `api/config/initializers/filter_parameter_logging.rb`
- Risk: phone/name values can appear in logs
- Confirm before fix:
  1. Send request with `contact_number`, `print_name`
  2. Inspect Rails logs
- Expected current behavior: values may be visible
- Verify after fix:
  1. Add campaign-specific sensitive params to filter list
  2. Confirm values are masked in logs

#### M3. OCR service logs extracted person data
- Area: `api/app/services/form_scanner.rb`
- Risk: PII in logs
- Confirm before fix:
  1. Execute OCR request with valid form
  2. Inspect logs for extracted name/village
- Expected current behavior: name/village logged in plain text
- Verify after fix:
  1. Remove/redact sensitive fields in logs
  2. Logs contain only operational metadata

#### M4. Poll watcher report lacks precinct-role ownership checks
- Area: `api/app/controllers/api/v1/poll_watcher_controller.rb`
- Risk: Any authenticated user can report any precinct
- Confirm before fix:
  1. Login as user assigned to one area
  2. Submit report for unrelated precinct
- Expected current behavior: likely accepted
- Verify after fix:
  1. Enforce assignment scope
  2. Unauthorized precinct report gets `403`

#### M5. Export/index query bounds are not constrained
- Area: `api/app/controllers/api/v1/supporters_controller.rb`
- Risk: large payload/DoS style pressure
- Confirm before fix:
  1. Request large `per_page` (e.g. `100000`)
  2. Run export over full dataset
  3. Observe response time/memory pressure
- Expected current behavior: unbounded values accepted
- Verify after fix:
  1. Enforce max `per_page` and export limits/batching
  2. Oversized requests are capped or rejected gracefully

#### M6. Long-running synchronous SMS loops in request cycle
- Area: `api/app/controllers/api/v1/events_controller.rb`, `api/app/controllers/api/v1/sms_controller.rb`
- Risk: timeouts, blocked workers under load
- Confirm before fix:
  1. Create large target set (motorcade/event notify)
  2. Trigger action and measure response duration
- Expected current behavior: request duration scales linearly with recipients
- Verify after fix:
  1. Move sends to background jobs
  2. Endpoint returns quickly with job status/queued response

#### M7. Realtime toast handler not defensive to malformed payloads
- Area: `web/src/hooks/useRealtimeToast.ts`
- Risk: runtime errors if payload shape changes
- Confirm before fix:
  1. Inject malformed websocket event (`data` missing keys)
  2. Observe UI/console behavior
- Expected current behavior: possible `TypeError`/broken toast flow
- Verify after fix:
  1. Add optional chaining/defaults
  2. Malformed event ignored or shown safely without crash

#### M8. Realtime toast timeout can update state after unmount
- Area: `web/src/hooks/useRealtimeToast.ts`
- Risk: React warning/memory leak pattern
- Confirm before fix:
  1. Trigger toast
  2. Navigate away within 5 seconds
  3. Watch console for state update on unmounted component warning
- Expected current behavior: warning can appear
- Verify after fix:
  1. Track/clear timers on unmount
  2. No warning after rapid navigation

---

### Low / Quality

#### L1. TypeScript strictness debt (`any`, unused vars) and lint failures
- Area: multiple frontend files
- Risk: hidden runtime issues and noisy quality signal
- Confirm before fix:
  1. Run `npm run lint` in `web/`
- Expected current behavior: many lint errors
- Verify after fix:
  1. Introduce shared API types and remove unused imports/vars
  2. Lint passes or improves with tracked baseline

#### L2. Minor API usage consistency issues in frontend
- Area: `web/src/pages/LandingPage.tsx`, `web/src/lib/api.ts` patterns
- Risk: maintainability inconsistencies
- Confirm before fix:
  1. Check direct axios calls vs wrapper usage
- Expected current behavior: mixed patterns
- Verify after fix:
  1. Standardize API access through `lib/api` helpers

---

## Suggested Execution Order (Fastest Risk Reduction)

1. Lock down ActionCable auth + role-gate SMS  
2. Verify/fix Netlify API routing and normalize environment config  
3. Fix websocket local dev URL mismatch  
4. Fix JWT claim verification + user provisioning policy  
5. Add PII log filtering/redaction  
6. Address query limits and background job offloading  
7. Resolve frontend lint/type debt and stale closure bug  

## Test Harness Notes

- Prefer creating lightweight automated checks while fixing each item:
  - Request specs for auth/role enforcement
  - Integration tests for websocket auth and message delivery
  - Frontend tests for StaffEntry duplicate warning and realtime toast safety
- If full test framework setup is deferred, keep manual test steps from this doc as acceptance criteria.
