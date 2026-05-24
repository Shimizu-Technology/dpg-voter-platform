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
- Mike Weekly involvement and training before the primary

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

These reports feed the War Room dashboard. This is useful, but for DPG it should be confirmed with Mike Weekly whether poll watchers should submit aggregate counts, individual checkoffs, or both.

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

### PR 2 — DPG Election Day Dashboard

Goal: admins/field organizers can monitor Election Day operations.

Backend scope:

- add DPG-scoped dashboard endpoint, likely adapted from `WarRoomController`
- permission such as `can_access_election_day_dashboard?` or `can_access_war_room?`
- aggregate by village/precinct:
  - active election-day GEC voters
  - precinct reports
  - turnout status counts
  - not-yet-voted linked DPG supporters
  - observed-elsewhere exceptions
  - ride-to-polls requests
  - unmatched approved supporters/contacts
  - recent reports/activity

Frontend scope:

- add Election Day Dashboard / War Room page
- DPG language and compact mobile/desktop views
- link to Poll Watcher page for allowed users
- remove motorcade/campaign-specific assumptions

Tests:

- poll watchers cannot access dashboard unless DPG explicitly allows it
- admins/field organizers can access dashboard
- dashboard respects village/district scope where applicable
- aggregate stats are correct

### PR 3 — User assignment/admin polish

Goal: make Poll Watcher role manageable by DPG admins.

Scope:

- Users page supports Poll Watcher role
- role permission matrix explains limited access
- assign one or more precincts to a poll watcher
- show assigned precincts in user management
- validate assignment rules
- possibly bulk assign watchers by precinct list

### PR 4 — Training/safety mode

Goal: safely train DPG poll watchers before Election Day.

Possible scope:

- training/test mode banner
- resettable training turnout data in non-production or explicit training environment
- test election mode flag if needed
- user-facing training checklist
- safe fake voter/contact records for rehearsal

## Open questions for DPG / Mike Weekly

See also `docs/dpg-open-questions.md` for the current walkthrough question list, including the key distinction between official GEC precinct/village for Election Day checkoff and separate DPG contact village for outreach.

Confirm before or during PR 1/PR 2 planning:

1. Should poll watchers mark individual voters, submit aggregate turnout counts, or both?
2. Should poll watchers be able to correct their own marks?
3. Who can clear `observed_elsewhere` or mistaken voted marks?
4. Should poll watchers see phone/contact info, or only GEC voter info?
5. Should out-of-precinct search be enabled for poll watchers or admin-only? If enabled, should poll watchers only file incidents, or can any trusted role mark an out-of-precinct voter as voted/observed elsewhere?
6. What should the dashboard prioritize: all GEC turnout, DPG supporters, members, registered Democrats, ride-to-polls, or a combination?
7. If a DPG contact's self-reported village differs from their official GEC registered village, should the app show them only in the GEC precinct list and surface the DPG contact village as context, or should DPG also want contact-village exception queues?
8. What training date is needed before the August 1 primary?
9. What language does DPG want for the dashboard: "War Room," "Election Day Dashboard," or another term?

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
