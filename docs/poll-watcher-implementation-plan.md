# DPG Poll Watcher / Election Day Implementation Plan

**Created:** May 23, 2026  
**Status:** Planned next major product track after PR #44  
**Reference implementation reviewed:** `../campaign-tracker` poll watcher and war-room implementation

## Decision

Poll watcher / Election Day operations should be the next major DPG build after the current docs/status cleanup and controlled beta QA.

The adjacent `campaign-tracker` application has a mature poll watcher and war-room implementation. We should use that implementation as the **technical blueprint** for DPG, while adapting the workflow, language, permissions, and dashboard assumptions to DPG's party operations needs.

This is not a direct copy of another campaign's private operating playbook. DPG explicitly requested poll watcher, voted/not-voted, and war-room/turnout workflows in the April/May meetings. The reusable technical pieces are legitimate to adapt as long as the DPG version is scoped around DPG requirements and does not import another campaign's data, branding, or private procedures.

## Why this is the right next build

DPG asked for:

- poll watcher workflow by assigned precinct
- real-time voted/not-voted tracking
- Election Day turnout visibility
- war-room style dashboard
- Mike Weakley involvement and training before the primary

The platform already has the foundations needed:

- GEC voter import/search/linking
- precincts and polling sites
- active election-day GEC import fields
- `poll_reports` table and `PollReport` model
- `poll_watcher_precinct_assignments` table
- GEC/supporter turnout columns
- `GecVoterTurnoutService`
- audit logs
- user/role infrastructure
- contact history
- ride-to-polls support request field

The missing work is mostly active routes/controllers, UI, permissions, tests, and DPG-specific wording/scoping.

## Campaign-tracker implementation reviewed

Key files reviewed in `../campaign-tracker`:

- `api/app/controllers/api/v1/poll_watcher_controller.rb`
- `api/app/controllers/api/v1/war_room_controller.rb`
- `api/app/models/poll_report.rb`
- `api/app/models/poll_watcher_precinct_assignment.rb`
- `api/app/services/gec_voter_turnout_service.rb`
- `api/db/migrate/*poll*`, `*turnout*`, and `*election_day*` migrations
- `web/src/pages/admin/PollWatcherPage.tsx`
- `web/src/pages/admin/WarRoomPage.tsx`
- `web/src/lib/api.ts`
- `web/src/App.tsx`
- `web/src/components/AdminShell.tsx`
- `web/src/pages/admin/UsersPage.tsx`
- `api/test/controllers/api/v1/poll_watcher_controller_test.rb`
- `api/test/controllers/api/v1/war_room_controller_test.rb`

## What is strong and reusable

### Active election-day GEC list

Campaign-tracker can mark a specific completed GEC import as the active election-day list. Poll watcher and war-room queries then operate against that list instead of accidentally using stale/future GEC rows.

DPG already has the active election-day import field and activation endpoint, so this pattern should be kept.

### Precinct-scoped poll watcher access

Campaign-tracker supports:

- `poll_watcher` role
- explicit `poll_watcher_precinct_assignments`
- assigned precinct access checks
- admin/coordinator broader access
- hard forbidden responses when users try to access an unassigned precinct

This maps well to DPG's stated need for precinct-scoped poll watcher accounts.

### Strike-list voter checkoff

Campaign-tracker's poll watcher page supports:

- select assigned precinct
- search active election-day GEC voters
- filter by turnout status
- mark voters as `voted`, `not_yet_voted`, `observed_elsewhere`, or clear/unknown
- optional notes
- supporter/contact overlays when voters are linked to CRM contacts

This is the closest match to DPG's voted/not-voted ask.

### Precinct reports

Poll watchers can submit reports such as:

- turnout update
- issue
- long lines
- closing
- name not on list

These reports feed the War Room dashboard. This is useful, but for DPG it should be confirmed with Mike Weakley whether poll watchers should submit aggregate counts, individual checkoffs, or both.

### Turnout update service and audit logging

`GecVoterTurnoutService` centralizes turnout updates and audit logging. It records:

- changed turnout status
- actor user
- timestamp
- note
- source
- registered precinct
- observation precinct for out-of-precinct sightings
- linked supporter/contact IDs
- compliance context that the app is campaign/party operations tracking, not official election records

This pattern should be reused.

### Observed-elsewhere handling

Campaign-tracker distinguishes in-precinct turnout marks from out-of-precinct observations. This is useful for Guam election operations because people may be observed at a polling site other than their registered precinct.

DPG should keep this concept, but the exact correction/reconciliation permissions should be confirmed.

### War Room dashboard

Campaign-tracker's War Room aggregates:

- village turnout
- precinct reporting
- not-yet-voted linked supporters
- observed-elsewhere exceptions
- unmatched supporters
- recent poll watcher reports
- call/follow-up attempts

The overall dashboard pattern is useful, but the DPG version needs different language and metrics.

## What must be adapted for DPG

### Language

Avoid campaign-specific wording where it does not fit DPG.

Prefer:

- Poll Watcher
- Election Day Dashboard
- DPG contacts
- DPG supporters
- voted / not yet voted
- turnout exceptions
- ride-to-polls requests
- priority follow-up
- DPG operations tracking only

Avoid or replace:

- campaign supporter, where DPG contact/supporter distinction matters
- motorcade
- Josh/Tina-specific war-room assumptions
- any private campaign operating labels

### Roles and permissions

DPG currently does not have active `poll_watcher` in `User::ROLES`. Add intentionally, with DPG-facing label "Poll Watcher".

Expected posture:

- Poll Watcher: assigned precinct voter/checkoff view only
- Field Organizer / Administrator: broader poll watcher access and correction/reconciliation
- Data Manager: likely election-day list management and audit/reconciliation, but not necessarily field checkoff unless DPG wants that
- Village Coordinator/Canvasser: no election-day tools unless DPG explicitly wants it

### Source validation

DPG currently validates turnout sources as `data_team` and `admin_override` in some models. Campaign-tracker uses `poll_watcher`. The DPG implementation must add `poll_watcher` as a valid turnout source before enabling turnout updates from poll watcher users.

### Ride-to-polls instead of motorcade

Campaign-tracker has motorcade-related stats. DPG should use `needs_election_day_ride` or voter assistance requests instead.

### DPG list constraints

Until DPG provides active/inactive/member/registered-Democrat list samples, the Election Day dashboard should rely on:

- GEC active election-day voters
- linked DPG contacts
- approved DPG supporters
- ride-to-polls requests

Do not invent official member-roster metrics before DPG list imports exist.

## Recommended implementation phases

### PR 1 — DPG Poll Watcher MVP

Goal: assigned poll watchers can search their precinct and mark voter turnout status.

Backend scope:

- add `poll_watcher` role to DPG role model
- add `can_access_poll_watcher?` permission
- add `require_poll_watcher_access!`
- expose assigned precincts for poll watchers
- add/adapt `Api::V1::PollWatcherController`
- add routes:
  - `GET /api/v1/poll_watcher`
  - `GET /api/v1/poll_watcher/strike_list`
  - `PATCH /api/v1/poll_watcher/strike_list/:voter_id/turnout`
  - optionally `POST /api/v1/poll_watcher/report`
  - optionally `GET /api/v1/poll_watcher/precinct/:id/history`
- allow turnout source `poll_watcher`
- preserve audit logging through `GecVoterTurnoutService`
- enforce assigned-precinct access at the API level

Frontend scope:

- add Poll Watcher route/page
- add sidebar/dashboard nav only when permission is present
- adapt `PollWatcherPage` from campaign-tracker with DPG wording
- mobile-first layout for polling-place use
- show compliance note: "DPG operations tracking only; not official election records."
- keep voter/contact details minimal for poll watchers

Tests:

- poll watcher can only see assigned precincts
- poll watcher cannot access other precincts
- poll watcher can mark assigned voter as voted
- poll watcher updates audit log
- linked DPG contact/supporter gets synced turnout status
- out-of-precinct observed-elsewhere behavior is correct
- non-poll-watcher roles cannot access restricted endpoints unless explicitly allowed

### PR 2 / PR #47 — Election Day Command Center bundle

Goal: finish the full operational Election Day loop after the Poll Watcher MVP: election setup/reset, selected GEC list, admin turnout dashboard, not-yet-voted chase list, contact logging, correction/reconciliation, and training readiness.

This can be implemented as one larger PR if we keep the scope disciplined and test it thoroughly. It should not be a vague “war room” copy; it should be DPG’s Election Day module with explicit election scoping and auditability.

#### 1. Election event foundation

Add an explicit election object before expanding dashboard/call-chase workflows.

Recommended model concept:

- `elections` / `election_events`
  - name, e.g. `2026 Primary Election`
  - election date
  - election type, e.g. primary/general/runoff/special
  - status, e.g. setup/training/active/closed/archived
  - active GEC import/list date for that election
  - created/updated/activated/closed by user

Why this matters:

- August and November must not share turnout counts.
- Historical turnout/checkoff data should remain available after an election closes.
- Training/test marks should be resettable or isolated.
- Poll Watcher should always show which election and GEC list it is operating against.

#### 2. Election-scoped turnout records

Move future Election Day tracking away from storing the only source of truth directly on `gec_voters.turnout_status`.

Recommended model concept:

- `election_turnout_records`
  - election_event_id
  - gec_voter_id
  - linked supporter/contact id when available
  - registered precinct/village from the election GEC list
  - observation precinct/village when different
  - turnout status: unknown/not_yet_voted/voted/observed_elsewhere
  - note/source/updated_by/updated_at

The existing `gec_voters.turnout_status` and `supporters.turnout_status` can remain as transitional/current-election convenience fields if helpful, but the durable record should be scoped to the election.

#### 3. Active GEC list rules

Election Day workflows should use the GEC list attached to the active election, not an implicit stale list.

Required behavior:

- admins/data managers can attach or switch the GEC import used for an election
- UI clearly shows election name, election date, GEC list date, and source filename
- changing the GEC list after turnout/checkoff has started requires a confirmation and audit log
- normal GEC monthly imports can continue, but Poll Watcher uses the selected election list
- if no election is active, Poll Watcher/Command Center should show setup-required messaging instead of silently using the wrong list

#### 4. Election Day Dashboard / Command Center

Admins/field organizers need a central dashboard showing turnout and follow-up state.

Backend scope:

- add DPG-scoped command-center endpoint, likely adapted from `WarRoomController`
- permission such as `can_access_election_day_dashboard?` or `can_access_command_center?`
- aggregate by village/precinct:
  - election-scoped GEC voters
  - turnout status counts
  - precinct reports
  - not-yet-voted linked DPG contacts/supporters
  - contacted/not-contacted Election Day follow-up counts
  - ride-to-polls requests
  - observed-elsewhere/name-not-on-list exceptions
  - recent poll watcher reports/activity

Frontend scope:

- add Election Day Dashboard / Command Center page
- DPG language and compact desktop/tablet/mobile views
- village/precinct drilldown
- voted list and not-yet-voted list
- “not yet voted and not contacted today” queue
- ride-to-polls and exception panels
- link to Poll Watcher for allowed users
- remove motorcade/campaign-specific assumptions

#### 5. Not-yet-voted chase list and call logging

The dashboard should support the actual DPG follow-up loop:

- list linked DPG contacts who have not yet voted
- filter by village, precinct, contact village vs GEC village, support status, ride need, contacted today, not contacted today
- log call/text/in-person attempts inline
- reuse `SupporterContactAttempt` for the durable contact history
- capture Election Day-specific outcomes such as:
  - reached, plans to vote
  - needs ride
  - already voted / says voted
  - wrong number
  - unreachable
  - refused / do not contact
- show who has already been called and who has not

#### 6. Correction and reconciliation rules

Required behavior:

- poll watchers can correct in-precinct marks they made, either by setting `not_yet_voted` or clearing to `unknown`
- admins/coordinators can correct any accessible election turnout mark with audit logging
- correction UI should show previous status, new status, actor, time, and optional note
- out-of-precinct observations remain exception/reconciliation items unless DPG confirms direct cross-precinct marking

#### 7. Assignment and training polish

If this bundle is the next PR, include the minimum admin setup needed so DPG can actually run training:

- assign poll watcher users to one or more precincts
- show assignments in user management or an Election setup screen
- training/test mode or resettable training election
- setup checklist: election created, GEC list attached, precinct assignments complete, poll watcher accounts ready

#### Tests for the bundled PR

- new election starts with clean turnout counts
- closed/archived election preserves historical turnout
- Poll Watcher uses the selected election’s GEC import/list date
- switching an election GEC list is permission-gated and audited
- poll watcher can mark and correct assigned in-precinct voters
- poll watcher cannot directly mark out-of-precinct voters
- admin/coordinator can reconcile exceptions
- dashboard aggregates voted/not-yet-voted by village/precinct correctly
- not-yet-voted chase list excludes voters already marked voted
- contact attempts logged from the command center appear in normal Contact History
- contacted/not-contacted counts update correctly
- ride-to-polls and name-not-on-list queues are visible
- role/permission boundaries hold for poll watchers, field organizers, coordinators, data managers, and admins

#### Scope caution

This is a large PR. It is acceptable as PR #47 only if it is treated as one cohesive vertical slice and validated locally before merge. If it becomes hard to review or test, split it into stacked PRs in this order: election event foundation, command center dashboard, chase-list/contact logging, assignment/training polish.

## GEC election-manual research notes

The Guam Election Commission Election Manual linked from `https://gec.guam.gov/` was reviewed on May 24, 2026. Relevant guidance supports a conservative DPG MVP:

- Poll watchers are observers for recognized parties/candidates. They may observe election conduct, issue voter challenges, and monitor voter participation.
- Poll watchers must not interfere with precinct officials, enter the barricade/voting area, access the official voter signature roster or official voter documents, ask voters for ID, speak to voters about marking ballots, or campaign/wear campaign identifiers.
- Wrong-precinct and not-on-roster situations are handled through precinct official/GEC procedures, including registration/polling-location checks and possible provisional ballots.
- Challenge grounds include precinct residency, whether the person voted that day, voted in another precinct, or voted in another U.S. jurisdiction.

Product implication: DPG poll watcher tools should remain explicitly unofficial DPG operations tools. Poll watchers can track DPG observations for assigned precincts, but out-of-precinct or name-not-on-list situations should be incident/exception reports unless DPG/Mike Weakley confirms a different workflow.

## Open questions for DPG / Mike Weakley

See also `docs/dpg-open-questions.md` for the current walkthrough question list, including the key distinction between official GEC precinct/village for Election Day checkoff and separate DPG contact village for outreach.

Confirm before or during PR 1/PR 2 planning:

1. Should poll watchers mark individual voters, submit aggregate turnout counts, or both?
2. Should poll watchers be able to correct their own marks?
3. Who can clear `observed_elsewhere` or mistaken voted marks?
4. Should poll watchers see phone/contact info, or only GEC voter info?
5. Should out-of-precinct search be enabled for poll watchers or admin-only? If enabled, should poll watchers only file incidents, or can any trusted role mark an out-of-precinct voter as voted/observed elsewhere?
6. What should the dashboard prioritize: all GEC turnout, DPG supporters, members, registered Democrats, ride-to-polls, or a combination?
7. If a DPG contact's self-reported village differs from their official GEC registered village, should the app show them only in the GEC precinct list and surface the DPG contact village as context, or should DPG also want contact-village exception queues?
8. For normal organizing reports outside Election Day, should DPG continue grouping people by DPG contact/signup village while Election Day tools group by official GEC registered precinct? Current product recommendation: yes, but make labels and exports explicit so staff understand both geographies.
9. What training date is needed before the August 1 primary?
10. What language does DPG want for the dashboard: "War Room," "Election Day Dashboard," or another term?

## Clean-room guardrails

Allowed to reuse/adapt:

- generic Rails/React architecture
- active election-day GEC import pattern
- precinct assignment model
- poll watcher access checks
- strike-list search/checkoff mechanics
- turnout update service/audit pattern
- realtime/dashboard primitives

Do not import:

- Josh/Tina data, users, logs, private workflows, or campaign-specific reports
- motorcade/yard-sign/event assumptions
- private war-room operating playbook
- campaign-specific terminology that DPG did not request

Implementation should be documented as DPG's own Election Day module because DPG explicitly requested poll watcher and turnout workflows.

## Readiness summary

The project is ready to start this build. The safest first implementation is the Poll Watcher MVP, not the full dashboard. The MVP can be built with conservative permissions and minimal poll watcher visibility, then expanded into the DPG Election Day Dashboard after DPG/Mike confirms operational details.
