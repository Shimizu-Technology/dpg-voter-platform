# DPG Remaining Work Roadmap

**Last updated:** May 23, 2026  
**Status:** Roadmap after PR #44 merged to `main` at `e0ceb08`

## Current posture

The core DPG voter engagement platform is now in controlled beta. The direct May 20 demo asks around GEC/address search, QR/signup-link lifecycle, quota/period foundation, SMS/email delivery visibility, failed-only resend, and intake review error/stale-row handling are implemented.

The remaining work is mostly operational validation, DPG-specific list/sample discovery, and larger Phase 2 modules that should be scoped with DPG before build.

## Immediate next work

### 1. Guided DPG beta QA

Run a small guided pass with Auntie Stephanie and a few DPG testers using safe records:

- public signup and QR signup
- Intake review and rejection/duplicate/invalid flows
- Contacts and contact detail
- GEC search, create-contact, link-contact, and possible-match confirmation
- Household/address lookup and household canvass logging
- Duplicate Contact Review
- Follow-Up Queue logging
- Reports preview/export
- Users/roles and scoped access
- SMS/email dry runs
- SMS/email delivery tables, refresh/sync controls, and failed-only resend

Success means DPG understands the workflow language and no critical beta blocker appears before broader use.

### 2. Production hardening

Confirm before broad real-data use:

- DPG-specific Render/Netlify/Neon/Clerk services and secrets
- DPG-specific database backups
- production Clerk branding/mode settings
- domain, CORS, and redirect settings
- ClickSend credentials/sender policy
- Resend sender/domain and `RESEND_WEBHOOK_SIGNING_SECRET`
- `DPG_LIVE_OUTREACH_ENABLED=true` only in the intended DPG environment
- controlled live SMS/email tests with approved recipients/content

### 3. Update tester handoff after real feedback

After the guided beta pass, update handoff language around anything DPG finds confusing:

- labels/status names
- role permissions
- Intake vs Contacts distinction
- GEC possible-match workflow
- quota/period meanings
- outreach delivery/resend language

## Next major product tracks

### 4. Election Day / poll watchers

This is the most important next feature area. The adjacent `campaign-tracker` application has a mature poll watcher and war-room implementation, and we should use it as the technical blueprint for DPG while adapting language, permissions, and assumptions to DPG's party operations needs. See `docs/poll-watcher-implementation-plan.md` for the detailed review and build plan.

Recommended phased scope:

1. Poll Watcher MVP:
   - Poll Watcher role
   - precinct/polling-place assignments
   - active election-day GEC list
   - mobile-first voter search/checkoff
   - voted/not-voted/observed-elsewhere status by voter and precinct
   - audit trail for every turnout/checkoff change
   - minimal poll watcher visibility
2. Election Day Dashboard:
   - village/precinct turnout summary
   - issue/escalation notes from polling places
   - not-yet-voted linked DPG supporters/contacts
   - ride-to-polls requests
   - observed-elsewhere reconciliation queue
   - admin/field organizer dashboard by village/precinct/time
3. User assignment/training polish:
   - precinct assignment UI
   - training/test mode
   - DPG/Mike Weekly training checklist

Open questions:

- What exactly can poll watchers legally/operationally record?
- Should they mark individual voters, submit aggregate counts, or both?
- Will they search by name, registration number, precinct list, or paper roster order?
- If a DPG contact village differs from the official GEC registered precinct/village, should Election Day checkoff stay strictly GEC-based while showing DPG contact context, or should DPG want contact-village exception queues?
- Who can correct a mistaken voted/not-voted mark?
- Should poll watchers see any DPG contact/phone info, or only GEC voter rows?
- How often does the dashboard need updates?
- What training date is needed before the August 1 primary?

Track the full question set in `docs/dpg-open-questions.md`.

Clean-room guardrail: do not copy Josh/Tina election-day operating workflows or private playbooks. Reuse only neutral platform primitives like roles, precincts, GEC voters, audit logs, and realtime updates, and implement DPG-specific language/workflows because DPG explicitly requested this module.

### 5. DPG list imports and list lineage

Blocked until DPG provides real samples/columns.

Needed file samples:

- active DPG list
- inactive DPG list
- official DPG member roster
- registered Democrat list
- supporter/contact lists
- any other custom lists DPG actually uses

Likely scope after samples:

- explicit list type selection
- import batch/source tracking
- preview/mapping/confirm
- duplicate and GEC match review
- list-lineage fields on contacts/reports
- official member-roster cross-reference
- registered Democrat vs DPG contact/supporter/member overlap reports

Guardrail: do not invent schemas or membership rules before seeing DPG files. DPG confirmed active/inactive lists exist and have retention rules, so avoid destructive purge assumptions.

### 6. Quota/period expansion

The foundation is merged. Detailed goal rules should wait for DPG feedback.

Possible next scope:

- goals by village, source link, organizer, or party-wide period
- raw signup vs approved contact vs supporter vs volunteer counts
- duplicate/unique-person credit rules
- leaderboard or progress dashboards if DPG wants them
- period close/reopen behavior
- what happens when an Intake record is approved after a period closes

### 7. Reports polish after list types

Already implemented: DPG/GEC cross-reference, linked/unlinked contacts, possible GEC matches, GEC voters not in DPG contacts, mismatch reports, supporter/referral/village/mapping/purge-style reports.

Still useful after list imports:

- official member-roster records not on GEC
- registered Democrats not in DPG contacts
- supporter/member/registered-Democrat overlap
- active vs inactive list reporting
- period-aware list conversion reports
- outreach delivery/resend summary reports
- Election Day turnout reports once poll watcher data exists

## Deferred add-ons

### 8. GIS / maps / heatmaps

Potentially useful, but defer until DPG confirms use case and data quality.

Possible future scope:

- map contacts/GEC voters where addresses geocode reliably
- village/precinct visualizations
- canvass route maps
- household clusters
- contact/supporter/turnout heatmaps

Risks/open items:

- Guam addresses and PO boxes may not geocode cleanly
- mapping providers add API/cost/privacy considerations
- role-based map visibility needs DPG approval

### 9. OCR / photo / ID scanning

Deferred until DPG defines the form/process and access rules.

Possible future scope:

- scan/import paper signup forms
- OCR extraction into an intake review queue
- human review before record creation
- optional ID/photo capture only with clear lawful/operational need

Guardrail: avoid Josh/Tina blue-sheet/OCR assumptions.

### 10. Autodialer integration

Deferred until DPG names the actual tool/process.

Possible first step:

- export call lists in the autodialer’s required format
- import call outcomes back into Contact History
- API integration only after tool selection and consent/compliance rules are clear

### 11. Advanced canvassing route/assignment tooling

Current household/contact logging is a foundation. More advanced route tooling can wait until DPG tests the existing workflow.

Possible future scope:

- field packets or route lists
- address-based assignments
- organizer progress by route
- offline/mobile considerations

### 12. Support/lean/donation tracking

DPG discussed support and donation concepts, but active workflow currently separates support status and volunteer status only. Add richer support/lean/donation fields only if DPG confirms they need them.

## Current blockers

- Real DPG list import work is blocked on sample files.
- Election Day work is blocked on DPG/Mike Weekly workflow scoping.
- GIS/OCR/autodialer work is blocked on confirmed use case, process, and tool decisions.
- Broad rollout is blocked on guided beta QA and production hardening.
