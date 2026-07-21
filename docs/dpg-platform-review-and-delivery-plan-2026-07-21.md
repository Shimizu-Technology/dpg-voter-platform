# DPG Voter Platform Review and Delivery Plan

**Review date:** July 21, 2026
**Branch reviewed:** `feature/dpg-election-day-command-center`
**Pull request:** #47, DPG Election Day Command Center

## Executive finding

This application is no longer just a voter-file search tool or a campaign CRM. It is a DPG-specific party operations platform that joins four operational records without conflating them:

1. the public GEC voter file;
2. DPG-entered contacts and outreach history;
3. future DPG-owned membership, active/inactive, and registered-Democrat lists; and
4. election-specific turnout observations and poll-site reports.

That separation is the central product and data-design requirement. The platform exists so DPG can organize island-wide voter engagement, preserve a durable contact history, reconcile its own lists against public voter records, and coordinate Election Day activity without relying on disconnected spreadsheets or another campaign's private system.

The core platform is substantial and usable. PR #47 fits as the completion of the first DPG Election Day operating loop: define one election, select its GEC list, assign poll watchers to exact precincts, record event-scoped turnout and reports, and turn the not-yet-voted result into accountable DPG follow-up. GIS, richer list lineage, OCR, and autodialer integration remain separate product modules.

## Why DPG asked for this

The April 2 and April 27 conversations consistently describe these problems:

- voter and party data is spread across files and manual processes;
- DPG needs the complete public voter file searchable by name, address, village, and precinct;
- field organizers need to see who should live at an address and record when/how they were contacted;
- DPG needs to distinguish its contacts, supporters, volunteers, registered Democrats, and official membership records;
- administrators need broad visibility while field and Election Day users must be geographically scoped;
- on Election Day, DPG poll watchers need to record who has voted so organizers can follow up with people who have not;
- leadership needs current turnout, precinct reporting, exceptions, and follow-up visibility;
- DPG wants mapping/heatmaps, but that depends on a defined map use case and sufficiently reliable geocoded addresses;
- OCR and autodialer ideas depend on DPG's actual forms and selected calling tool.

This is a party-wide system. It must remain isolated from Josh/Tina data, branding, prompts, users, scripts, and operating playbooks. Reusable technical primitives are appropriate; private campaign data and campaign-specific workflows are not.

## How the application works

### Public intake and attribution

Residents can enter through the public signup flow or a DPG-created signup/QR link. The system records source attribution, creates an Intake record, and waits for staff review rather than automatically counting every signup as a supporter.

### DPG contact operations

Staff review Intake, classify the record, track support and volunteer status separately, connect the contact to a GEC voter when appropriate, and preserve calls, texts, emails, and in-person touches in Contact History. Follow-up queues, households, outreach, duplicates, and reports operate on that governed contact record.

### Public voter-file operations

Administrators and data staff import dated GEC files. GEC records remain official-source context; a confirmed match links a DPG contact to a GEC voter without overwriting DPG-entered information. Household and cross-reference views intentionally show the two sources separately.

### Roles and geographic scope

The active roles are Administrator, Data Manager, Field Organizer, Village Coordinator, Canvasser, and Poll Watcher. Administrators and Data Managers have island-wide administrative/data access; field roles are district/village scoped. Poll Watchers are now scoped to explicit precinct assignments rather than inheriting a whole village.

### Election Day operations

An Administrator or Data Manager creates an election event and attaches a completed, dated GEC import. The event can be started in training or activated live. Poll Watcher reports and individual turnout observations belong to that specific event. The Command Center aggregates turnout, recent poll reports, observed-elsewhere exceptions, ride requests, and linked DPG contacts who have not yet voted. DPG follow-up is logged into ordinary Contact History, so Election Day work does not become a disconnected data silo.

## Current feature assessment

| Product area | Current status | Finding / next requirement |
|---|---|---|
| DPG-specific deployment and clean-room boundary | Implemented | Preserve separate repo, services, auth, secrets, database, and backups. Never introduce another campaign's data or playbook. |
| Public signup, QR links, source attribution | Implemented | Validate wording and attribution with DPG testers; used links should be archived, not destructively removed. |
| Intake review and contact classification | Implemented | The separation of record status, support status, volunteer status, and contact history is correct. |
| Contacts, households, address search | Implemented | Continue real-file QA for Guam address variants. This is the data-quality foundation for any future GIS work. |
| GEC import, search, match, and history | Implemented | Monthly production confidence still requires representative DPG/GEC file QA and an operational import owner. |
| Duplicate review and audit history | Implemented | Keep corrections auditable and restrict destructive/data-export operations. |
| SMS/email outreach and delivery retry | Implemented | Production credentials, sender policy, consent rules, and controlled live tests remain operational gates. |
| Reports and DPG/GEC cross-reference | Implemented foundation | Official member, active/inactive, and registered-Democrat reports are blocked on actual DPG list files and definitions. |
| Quota/outreach periods | Implemented foundation | DPG still needs to define what counts, who owns goals, unique-person credit, and closed-period behavior. |
| Poll Watcher voter search/checkoff | Implemented in PR #46/#47 | Requires a supervised DPG/Mike walkthrough and rehearsal with real precinct assignments. |
| Election event and Command Center | Implemented and hardened in PR #47 | Requires rehearsal, scale verification, correction drills, and final DPG terminology approval. |
| Poll watcher exact precinct assignment | Implemented in this PR revision | Assignment is explicit and manager-scoped; legacy village fallback is removed. |
| Election training mode | Implemented in this PR revision | Training is a separate event. It must be closed and followed by a clean live event; practice data never carries forward. |
| GIS/maps/heatmaps | Requested; deferred/additional | Define the decision the map supports, test geocoding coverage/accuracy, approve map provider/cost/privacy, then build a bounded pilot. |
| OCR/photo/paper form intake | Requested possibility; deferred | Needs actual DPG forms, retention/access rules, confidence thresholds, and mandatory human review. |
| Autodialer | Requested possibility; deferred | Needs the selected vendor/tool, consent/compliance process, required import/export format, and outcome synchronization rules. |
| Rich support/lean/donation tracking | Partially represented; not fully scoped | Support and volunteer states exist. Add lean/donation fields only after DPG defines allowed users, meaning, and reporting need. |

## How PR #47 fits and what was incomplete

The original PR had the correct overall product shape, but review found several gaps that could make a demo look complete while leaving operational risk:

1. New election events could display turnout copied from global legacy GEC fields, allowing one election or rehearsal to contaminate another.
2. Poll reports were associated only by precinct and timestamp, so an event could accidentally display another event's report.
3. The assignment model existed, but Users had no way to select exact precincts; Poll Watcher still had a village-level fallback.
4. `training` existed as a model status but had no supported transition or visible operational workflow.
5. The Command Center loaded the full GEC population and chase list into Ruby memory, which is inappropriate for a roughly 52,000-row voter file.
6. The role disclosure omitted Command Center access, and one emoji remained in an internal UI despite repository guardrails.
7. Product/status documentation still described Election Day as future work.
8. Analytics configuration allowed autocapture and session replay in a political-data application, and page views could include query strings.
9. Dependency scans needed to be rerun against the current lockfiles rather than relying on older green CI results. The vulnerable Ruby and npm dependency sets were updated in this revision, both audits now report zero known vulnerabilities, and npm audit is now enforced in CI.

## PR #47 completion work

This branch revision addresses the product-critical gaps:

- turnout defaults are now clean per election event and never seeded from legacy/global GEC turnout;
- training turnout stays inside the training event and does not sync into legacy/global live fields;
- the database permits only one current training-or-live event;
- training has an explicit start action, visible warning state, audit metadata, and required close-before-live workflow;
- new poll reports carry an `election_event_id`, and Command Center/history queries use that relationship rather than calendar dates;
- poll reports and turnout updates require a current training or live event;
- Poll Watchers receive exact active precinct assignments through Users, with district-scoped assignment enforcement for Field Organizers;
- Poll Watcher access no longer falls back to an entire assigned village;
- Command Center counts/aggregates run in SQL, chase contacts are server-filtered and paginated, and exception/report collections are bounded;
- the UI exposes search, filters, pagination, training controls, status warnings, and correct role permissions;
- political analytics are reduced to deliberate aggregate events: autocapture and session recording are disabled, signup political attributes are not sent, staff geography is not identified, and page URLs exclude queries;
- tests cover event isolation, training behavior, report scoping, bounded chase pages, and exact precinct assignment.

## Required validation before DPG relies on Election Day operations

Code completion is not the same as operational readiness. Run one supervised training event with Mike and the DPG team:

1. Create a clearly named training event with the intended GEC list.
2. Assign at least two test Poll Watchers to exact precincts and confirm they cannot open other precincts.
3. Search by roster order/name/registration details using representative records.
4. Mark voted, correct a mistake, and record observed elsewhere/not-on-list cases.
5. Submit aggregate turnout and issue reports from more than one precinct.
6. Confirm Command Center counts, village totals, recent reports, exceptions, and chase filters update as expected.
7. Log a call, SMS, and in-person follow-up and confirm Contact History/audit attribution.
8. Test ride-request filtering and the handoff process for exceptions.
9. Close training and prove updates are locked.
10. Create a new live event on the same GEC list and prove every voter begins `not yet voted` with no training reports or turnout carried forward.
11. Confirm who is authorized to correct individual turnout and what DPG calls each report/status.
12. Record the named owner for live event creation, GEC import selection, assignments, monitoring, correction, and event closeout.

## GIS/heatmap recommendation

GIS is a real DPG request, not an invented backlog item. It is also not a single feature. The April discussion includes at least three possible products: a map of voters in a precinct, a density/heat view for leadership, and a field canvassing/route tool. Those require different data, permissions, and interfaces.

Recommended sequence:

1. choose one first decision, such as “show reliable canvassable GEC households in a selected precinct”;
2. measure geocoding coverage and accuracy on a representative, non-production sample, separating street addresses from PO Box/HCR records;
3. define whether exact points, generalized blocks, or aggregate cells may be shown to each role;
4. select a provider after cost, Guam coverage, retention, and data-processing review;
5. pilot one village/precinct and display unmatched/low-confidence rates instead of silently dropping records;
6. add heatmaps only when the underlying denominator and metric are explicit (registered voters, contacts, supporters, contacted households, or election turnout).

Until those steps are complete, list/table/household workflows are more trustworthy than a visually impressive but incomplete map.

## Remaining launch and operations work

- Keep the now-clean Ruby and npm dependency audits enforced in CI and review future update failures promptly.
- Confirm daily automated database backups and a tested restore procedure.
- Confirm DPG-only production services, credentials, CORS, domains, Clerk production mode/branding, and least-privilege access.
- Decide whether PostHog should be enabled at all in production; if enabled, retain the privacy-minimized configuration and document retention/access.
- Run representative GEC import and 52,000-row Command Center performance checks against staging-like infrastructure.
- Obtain and define DPG active, inactive, official member, and registered-Democrat files before implementing list-specific lineage or reports.
- Complete the supervised Election Day rehearsal and update the tester/runbook documentation with DPG's final terminology and owners.

## Source basis

Repository sources reviewed include the application architecture/models/controllers/frontend, migrations, tests, deployment/configuration, PR #47 diff and review history, and all active planning/status documents under `docs/`.

DPG context was cross-checked against these Brain Dump sources:

- `work/shimizu-tech/Democratic-Party/2) - Democratic Pary Meeting with Mrs. Stephanie and her team - April 2nd, 2026.md`
- `work/shimizu-tech/Democratic-Party/1) - In Person meeting with Auntie Stephanie and Ethan - April 27, 2026.md`
- `work/shimizu-tech/Democratic-Party/3) Demoing app with the Democratic Party.md`
- `work/shimizu-tech/democratic-party-guam-voter-platform.md`
- `work/shimizu-tech/dpg-campaign-tracker-implementation-plan-2026-05-08.md`
- `work/shimizu-tech/dpg-voter-platform-current-status-2026-06-15.md`
- `work/shimizu-tech/campaign-boundaries-dpg-josh-tina-2026-05-08.md`
- `system/open-loops.md`

Where the transcripts describe an idea but do not define the workflow, this review marks it as pending DPG definition rather than implemented or promised.
