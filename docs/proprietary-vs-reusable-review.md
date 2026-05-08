# Proprietary vs Reusable Review — Josh/Tina → DPG

**Review basis:** Re-review of all Josh/Tina campaign transcripts, with special attention to Frank Arriola meetings:

- `8) - April 4, 2026 - Meeting with Mr. Frank Arriola for the campaign.md`
- `9) - April 29, 2026 - Meeting with Frank for Josh Tina Campaign.md`
- Other Josh/Tina transcripts from Feb 14, Feb 24, Mar 15, Mar 20, Mar 22, Apr 2 Derek/Tina meetings.

## Core conclusion

We do **not** need to remove every feature that was built during Josh/Tina work.

Frank's distinction is more nuanced:

1. Shimizu/Leon owns the software/application/code.
2. Josh/Tina owns the campaign database/data.
3. Josh/Tina wants its specific operating method/playbook protected, especially the manual campaign system/process that was automated with Rose/Trish/Frank.

So the DPG repo should keep reusable platform capabilities, but avoid carrying over Josh/Tina-specific data, labels, reports, assumptions, workflows, and operating playbook.

## Frank red lines

### Code/application ownership

Frank explicitly distinguishes software ownership from campaign data ownership.

Relevant Frank-meeting concepts:

- “You own this software, this application. The code. The code. You own it.”
- Leon/Shimizu licenses/runs the application; campaign owns the data created in it.
- Agreement should state Shimizu owns application/code and Josh/Tina owns data/database.

### Josh/Tina data ownership

Josh/Tina owns:

- campaign database
- supporter/voter records they collected
- uploaded files/lists
- audit/user activity for their campaign
- final export/database generated from the campaign's work

Do not copy Josh/Tina data/users/logs/seeds/examples into DPG.

### Protected operating playbook

Frank's proprietary concern is the campaign method, not generic software categories.

Protected/high-risk:

- Rose's manual voter-acquisition process as automated in the app
- the exact quota/village-org process and cadence
- the exact review/vetting/approval gates the data team uses
- specific report formats that encode their process
- internal field/data-team structure and responsibilities
- operational dashboards tuned to their campaign method
- election-day/poll/war-room workflow if it mirrors their local operating process
- anything derived from Rose's “six pages” or the campaign's years of local practice

### Commercialization concern

Frank's concern is not that Leon builds campaign software generally. His concern is selling Josh/Tina's specific system/method to another campaign/competitor.

Therefore DPG can receive a Shimizu-built DPG platform, but it should not be positioned or built as “the Josh/Tina system.”

## Safe reusable platform capabilities

These are Shimizu-created/general platform features and should **not** be removed just because they were first built during Josh/Tina work:

- Rails/React/Postgres architecture
- public supporter/signup form
- staff/admin manual entry
- CSV/Excel import/export
- duplicate detection and merge/review mechanics
- user management
- role-based access control
- audit/activity logs
- SMS/email plumbing and opt-in logic
- generic CRM/supporter records
- village and precinct data models where used generically
- district data structures only if they use neutral/public DPG-defined districts, not Josh/Tina internal district mapping
- QR signup links as generic access/marketing mechanism
- generic OCR/photo intake as a neutral platform feature, if later scoped
- generic GEC/public voter-list import/search/matching
- generic dashboards/reports that do not encode Josh/Tina's process
- generic poll watcher/election-day tooling as a concept, if rebuilt/scoped from DPG requirements later
- voter-help/follow-up lists as generic civic assistance workflow

## Items to keep, remove, or ask

### Keep for DPG now

- DPG-branded public signup/thank-you flow
- supporter/contact CRM
- manual staff entry
- CSV/import/export foundation
- duplicate review
- contact/follow-up status
- user/role management
- villages and precincts
- districts only after confirming they are DPG/public-neutral, not inherited Josh/Tina district mapping
- audit logs
- SMS/email settings/plumbing, with live blasts only after approval
- GEC/public voter-list mechanics if DPG needs them and they are implemented generically

### Remove/keep inactive unless DPG defines their own version

- hardcoded Josh/Tina names, URLs, copy, assets, defaults
- Josh/Tina users/data/seeds/example records
- quota/campaign-cycle dashboards that reflect Josh/Tina village-org cadence
- Josh/Tina internal district mapping or team-to-district assignments
- motorcade/yard-sign fields and UI assumptions
- Rose/Trish-specific review flow labels or approval rules
- war-room dashboard if it mirrors Josh/Tina's operating model
- poll watcher workflow if it mirrors Josh/Tina's process rather than a new DPG-scoped process
- reports named/structured around Josh/Tina's quota submissions
- Derek/Tina side-channel/shared-login/access assumptions

### Ambiguous — do not delete blindly

These may be valuable platform features but need genericization or DPG-specific scoping:

- Quotas/goals: DPG may need goals/targets, but not Josh/Tina's quota cadence/process.
- Poll watcher: DPG explicitly discussed poll watcher/election-day concepts, but we should rebuild/configure based on DPG requirements, not copy Josh/Tina's flow.
- War-room/turnout: useful concept, high-risk if it reproduces Josh/Tina operating model.
- OCR/scan: DPG mentioned possible photo/OCR import; keep as future neutral feature, not Monday requirement.
- GEC matching: generally safe because public voter-list matching is generic and DPG requested it; avoid Josh/Tina-specific statuses/reporting.
- QR: safe generic feature; removal is not required if implemented as generic signup/share QR.
- Dashboard/reporting: safe if generic; risky if it encodes quota/village-chief workflow.
- District mapping: Guam village/precinct geography is public/generic, but Josh/Tina team/district mapping should be treated as sensitive and removed or rebuilt from DPG requirements.

## DPG requested/needed functionality

### Starter / Monday scope

- DPG-branded public landing/signup/thank-you
- staff/admin login
- supporter/contact registry
- DPG-owned list import
- search/filter by village/precinct; district only if DPG defines/approves its own district grouping
- contact logging and follow-up status
- duplicate detection/review
- users/roles/permissions
- basic reports/export

### Next phase

- GEC voter list import/search/cross-reference
- DPG membership/supporter list cross-reference against GEC voter file
- household/address lookup
- canvassing contact attempts and status history
- mass SMS/email reminders after opt-in/sender/legal details are approved
- QR/public signup improvements
- precinct/village organizing views; district organizing views only after DPG defines its own mapping

### Later / explicitly scoped only

- poll watcher/election-day command center
- turnout/voted-not-voted tracking
- war-room dashboards
- GIS/heatmaps
- ID scanning
- OCR/photo paper-form ingestion
- AI/automation
- party-specific goals/quotas if DPG defines them

## Practical cleanup guidance

Do not delete features just because their names appeared in Josh/Tina meetings.

For each feature ask:

1. Is this generic software Leon/Shimizu built?
2. Does DPG explicitly need it or is it a neutral foundation?
3. Does the implementation contain Josh/Tina data, terms, flow assumptions, or report logic?
4. Can it be renamed/generalized or should it be removed from active DPG UI/API?

If answer is generic + useful + no Josh/Tina playbook, keep it.
If answer is Josh/Tina-specific process/data/reporting, remove or keep inactive until DPG scopes their own equivalent.

## Recommendation update

The earlier cleanup plan was appropriately cautious, but it may have been too aggressive if interpreted as “delete all poll watcher/GEC/QR/OCR/dashboard concepts.”

Better approach:

- Remove Josh/Tina-specific implementation details.
- Keep neutral platform mechanics.
- Reintroduce/enable features only when they are either generic or directly grounded in DPG transcripts.
- Document any ambiguous feature before deleting it permanently.
