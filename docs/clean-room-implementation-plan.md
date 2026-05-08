# Clean-Room Implementation Plan — DPG Voter Platform

## Decision

DPG should remain a separate application/repository, not a reskinned Josh/Tina deployment.

The goal is to reuse Shimizu Technology's neutral platform foundation while removing Josh/Tina campaign-specific workflows, assumptions, data, reports, and operating playbook details. DPG features should be added from DPG's own meeting transcripts and requirements.

## Boundary rule

- **Allowed:** reusable code, UI components, auth, CRM records, import/export infrastructure, public signup, role-based access, audit logs, SMS/email plumbing, public Guam voter-list/GEC mechanics.
- **Not allowed by default:** Josh/Tina data, users, logs, branding, social copy, quota/village-org methodology, Rose/Trish/Frank-specific review workflows, campaign-specific dashboards/reports, election-day operating model, motorcade/yard-sign assumptions, or any workflow copied because it existed in Josh/Tina rather than because DPG requested it.

## What has already been done

- Created a dedicated local/GitHub DPG repo: `Shimizu-Technology/dpg-voter-platform`.
- Made DPG the default identity, not an environment-selected variant.
- Removed active navigation/routes for deferred/proprietary-feeling modules:
  - War Room
  - Poll Watcher
  - Events
  - QR/leaderboard surfaces
  - OCR scan route
  - Quotas/cycles UI
  - public review/GEC vetting queue UI surfaces
- Replaced top-level README/AGENTS/docs with DPG-specific guardrails.
- Added deployment checklist and Monday testing handoff.
- Verified initial checkpoint with lint/build/zeitwerk/route and leak scans.

## Current audit findings before deployment

The app is much cleaner, but the source still contains inherited internals that should be addressed before or immediately after first staging deploy:

### Remove or neutralize before staging if practical

1. **Campaign/quota residue**
   - `Quota`, `QuotaPeriod`, `VillageQuota`, `CampaignCycle` models/migrations/tests still exist.
   - Dashboard/report code still computes quota progress.
   - Seeds still create quota/cycle records.
   - Recommendation: remove from active DPG dashboards/reports now; decide later whether DPG needs a party-specific goals system.

2. **Motorcade/yard-sign residue**
   - `supporters.motorcade_available` remains in schema and indexes.
   - Recommendation: hide from UI/API responses if still present; replace later with DPG-specific volunteer-interest fields if needed.

3. **Election-day/poll watcher residue**
   - Some models/services remain, e.g. poll watcher assignments/reports and GEC turnout service.
   - Routes are stripped, but code/schema residue should be removed or documented as intentionally inactive.
   - Recommendation: keep out of active UI/API for Monday; only rebuild later from DPG's own election-day requirements.

4. **OCR/scan residue**
   - OCR/scan route is removed, but tests/services/controllers may still exist.
   - DPG mentioned possible paper/photo/OCR import, but it should be treated as Phase 2 unless DPG explicitly prioritizes it.

5. **Generic branding residue**
   - Some static metadata still says `Campaign Tracker`.
   - Recommendation: rename visible/static metadata to `DPG Voter Platform` or `Democratic Party of Guam Voter Engagement Platform`.

### Safe to keep for Monday if cleanly scoped

- Public DPG signup.
- Supporter/contact CRM.
- Manual entry.
- CSV/Excel import for DPG-owned lists.
- Duplicate review.
- Basic contact/outreach status.
- Users/roles.
- Villages/districts/precincts.
- Audit logs.
- SMS/email configuration pages, with live sends disabled until approved.
- GEC voter-list import/search/matching if it is based on public GEC data and DPG requirements, not Josh/Tina workflow assumptions.

## DPG requested functionality from transcripts

### Monday / starter scope

- DPG-branded public landing/signup/thank-you flow.
- Staff/admin login.
- Supporter/contact registry.
- Import DPG-owned supporter/member lists.
- Search/filter by village/precinct/district where available.
- Basic contact logging and follow-up status.
- Duplicate detection/review.
- Users/roles with scoped permissions.
- Reports/export basics.

### Next phase after Monday

- GEC voter list import/search/cross-reference.
- DPG membership list cross-reference against voter file.
- Household/address lookup.
- Canvassing contact attempts and status history.
- Mass SMS/email reminders after sender/legal/opt-in details are approved.
- QR/public signup improvements.
- Precinct/village/district organizing views.

### Explicitly defer until separately scoped

- Poll watcher/election-day command center.
- Turnout/voted-not-voted operations.
- War-room dashboards.
- GIS/heatmaps.
- ID scanning.
- OCR/photo paper-form ingestion.
- AI/automation.
- Any quota/village-org workflow unless DPG defines their own version.

## Recommended sequence before isolated deployment

1. **Commit this clean-room plan.**
2. **Run a second cleanup pass:**
   - rename remaining visible `Campaign Tracker` metadata;
   - remove/hide quota/motorcade references from active DPG dashboard/report/session payloads;
   - confirm stripped modules are unreachable by route and UI.
3. **Run verification:**
   - frontend lint/build;
   - Rails zeitwerk/routes;
   - source and built-output leak scan;
   - smoke test core flows locally if possible.
4. **Then deploy staging with isolated DB/auth/secrets.**
5. **After staging:** add DPG-specific functionality from their transcripts in small, documented increments.

## Working principle

Do not ask: “Can DPG use this Josh/Tina feature?”

Ask: “Did DPG request this, and can we implement it as a neutral/DPG-specific workflow without carrying over Josh/Tina's private operating method?”
