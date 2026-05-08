# DPG Build — Simple Remove/Add Plan

**Purpose:** Make the DPG app clean, useful, and defensible: keep Shimizu-built reusable platform functionality, remove Josh/Tina-specific data/workflows/playbook, then add DPG-specific needs from DPG's own meetings.

## Why we are doing this

We are building DPG as its own app, not a Josh/Tina clone.

The boundary from the Frank/Josh-Tina meetings is:

1. **Shimizu Technology owns the software/code/platform.**
2. **Josh/Tina owns their data/database.**
3. **Josh/Tina's specific operating playbook should stay protected.**
4. **DPG gets a separate app based on DPG's own requirements.**

So we do **not** remove every good feature we built. We remove Josh/Tina-specific implementation details and keep/reuse neutral platform capabilities.

## Guiding rule

For every feature, ask:

> Is this generic platform functionality, or does it encode Josh/Tina's campaign method?

- If it is generic and useful to DPG: **keep it**.
- If it is Josh/Tina data/branding/process: **remove it**.
- If it could be useful but currently mirrors Josh/Tina's method: **disable it now, rebuild later from DPG requirements.**

---

# What to remove or disable

## 1. Josh/Tina identity/data

Remove completely:

- Josh/Tina names, copy, URLs, logos, social links, images
- Josh/Tina users/staff records
- Josh/Tina supporter/voter records
- Josh/Tina uploaded lists/files
- Josh/Tina audit logs or activity data
- Josh/Tina seed/demo data

**Why:** This is client data/branding and should never appear in DPG.

## 2. Blue block-list form workflow

Remove or rebuild:

- Any UI/copy/schema that specifically mirrors Josh/Tina's blue block-list form
- Any scan/OCR flow that assumes that blue form
- Any labels/statuses that came from that form instead of DPG requirements

**Why:** The blue block-list digitization is tied to Josh/Tina's voter-acquisition process.

## 3. Rose/data-team vetting process

Remove or make generic:

- Rose/Trish-specific review queues
- Josh/Tina-specific approval gates
- “accept to quota” workflow
- data-team handoff logic that mirrors their internal process
- statuses/reports that exist only because of their vetting flow

**Why:** Frank's concern was protecting their operating method, especially the little details around how the team processes voter data.

## 4. Quota/village-org campaign cadence

Disable/remove from active DPG UI/API:

- quota periods
- campaign cycles
- village quota dashboards
- quota progress reports
- monthly quota assumptions
- village-chief/block-leader quota flow

**Why:** DPG may need goals someday, but not Josh/Tina's quota process.

## 5. Josh/Tina district mapping

Remove or start empty:

- inherited district groupings
- team-to-district assignments
- any district mapping based on Josh/Tina's internal structure

Keep:

- Guam villages
- public precinct data

**Why:** Villages/precincts are public/generic. Josh/Tina district grouping may reflect campaign strategy.

## 6. Campaign-specific logistics

Remove unless DPG asks for equivalents:

- motorcade fields
- yard-sign fields
- event/parade assumptions
- leaderboard/gamified collection targets

**Why:** These are campaign-specific tactics, not core DPG starter needs.

## 7. Election-day command center / war room

Keep inactive for now:

- war room dashboard
- voted/not-voted operations
- poll watcher workflows
- turnout command center

**Why:** These concepts can be generic and DPG did mention poll watcher/election-day needs, but we should not ship Josh/Tina's implementation. Rebuild later from DPG's own process.

## 8. Static metadata cleanup

Rename remaining visible/static labels:

- `Campaign Tracker` → `DPG Voter Platform` or `Democratic Party of Guam Voter Engagement Platform`

**Why:** DPG should feel like its own app, not a repackaged campaign tracker.

---

# What to keep

These are reusable Shimizu-built platform capabilities and should not be removed just because they were first built during Josh/Tina work.

## Keep for Monday/starter app

- DPG-branded public landing/signup/thank-you
- supporter/contact CRM
- staff/admin login
- manual staff entry
- CSV/Excel import for DPG-owned lists
- duplicate detection/review
- basic contact logging
- follow-up/outreach status
- users/roles/permissions
- audit logs
- reports/export basics
- villages and public precinct references
- SMS/email settings/plumbing, but no live blasts without approval

## Keep as generic foundation

- Rails/React/Postgres app architecture
- auth/session structure
- reusable UI components
- import/export infrastructure
- public signup flow
- audit/activity infrastructure
- generic GEC/public voter-list import/search/matching
- QR signup/link generation, if generic
- OCR/photo intake infrastructure only as future neutral foundation, not active Monday scope

---

# What to add for DPG

## Monday / first testing build

Add or verify:

1. DPG branding everywhere
   - logos
   - app name
   - metadata
   - public page copy

2. Clean DPG supporter/contact flow
   - public signup
   - admin/staff manual entry
   - contact detail page
   - follow-up status
   - notes/contact history

3. DPG-owned import path
   - import member/supporter CSV/Excel
   - preview mapping
   - confirm import
   - duplicate review

4. Basic DPG admin setup
   - admin/staff login
   - user roles
   - permissions
   - no Josh/Tina users

5. Village/precinct organization
   - keep villages
   - keep public precinct references if available
   - leave district mapping empty unless DPG defines it

6. Basic reporting/export
   - supporter/contact export
   - simple counts by village/precinct/status
   - no quota-specific reports

## Next phase after Monday

Add from DPG requirements:

- GEC voter-list import/search/cross-reference
- DPG membership list cross-reference against GEC voter file
- household/address lookup
- canvassing contact attempts/history
- QR signup improvements
- SMS/email reminders after opt-in/sender/legal approval
- precinct/village organizing views
- DPG-defined district grouping, if they want districts

## Later / separately scoped only

Only add after DPG explicitly defines the workflow:

- poll watcher/election-day command center
- turnout/voted-not-voted tracking
- war-room dashboard
- GIS/heatmaps
- ID scanning
- OCR/photo paper-form intake
- AI/automation
- party-specific goals/targets

---

# Safe implementation order

Do this in small chunks so we do not break the app.

## Step 1 — Audit active surfaces

Check:

- frontend navigation
- Rails routes
- dashboard payloads
- reports
- seeds
- public pages
- static metadata

Goal: identify anything Josh/Tina-specific still reachable.

## Step 2 — Hide/disable before deleting

Disable risky modules from UI/API first:

- quota/cycles
- inherited district mapping
- motorcade/yard signs
- war room/poll watcher
- blue-form scan/vetting

Goal: Monday app stays stable.

## Step 3 — Remove visible residue

Remove visible/copy-level residue:

- names
- labels
- static metadata
- old docs
- old demo data

Goal: no Josh/Tina or generic “Campaign Tracker” leakage.

## Step 4 — Run verification

After each cleanup chunk:

- `npm --prefix web run lint`
- `npm --prefix web run build`
- `RAILS_ENV=test bundle exec rails zeitwerk:check`
- Rails route scan
- source/dist leak scan

## Step 5 — Add DPG features from DPG requirements

Only after cleanup is stable:

- strengthen DPG CRM/import flows
- add DPG-specific labels/copy
- add GEC/member cross-reference if ready
- add DPG-defined district mapping if approved

---

# Bottom line

We are not throwing away our hard work.

We are keeping the reusable Shimizu-built platform, removing Josh/Tina's data and operating playbook, and shaping the DPG app around DPG's own needs.
