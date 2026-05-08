# Poll Watcher Operations Spec

Last updated: 2026-04-20

This document defines what poll watchers do on election day and how that maps to the app workflow.
It is the reference for the full-voter poll watcher workflow described by Becky.

Current branch implementation note:

- the poll watcher strike list now uses the assigned full GEC voter list
- the election-day list can be explicitly frozen by activating a completed GEC import
- poll watcher access can be narrowed to explicit precinct assignments, with assigned-village scope retained as fallback for existing accounts
- campaign supporter details are overlaid when a GEC voter is linked to one or more approved campaign supporters
- war room supporter call queues are derived from linked supporters whose GEC voter turnout status is `not_yet_voted`
- unmatched supporters are surfaced separately because they cannot be safely derived from the full-voter turnout list until matched
- rollout is not complete until realistic precinct QA, operator training, and manual rehearsal sign-off are captured

---

## Purpose

- Give the campaign a fast, repeatable way to track turnout against the full registered voter list during election day.
- Keep field updates scoped to assigned precincts.
- Feed war room call lists in near real-time by overlaying campaign supporters on top of full-voter turnout data so "not yet voted" supporters can be contacted.

Important: this is campaign operations data, not official election records.

---

## Poll Watcher Role Scope

Poll watchers are election-day operators focused on turnout reporting.

### Allowed
- Access `Poll Watcher` election-day tools.
- View only precincts they are assigned to.
- Submit precinct turnout snapshots and issue flags.
- Mark turnout status against the full assigned precinct voter list.

### Not Allowed
- Access supporter CRUD pages outside election-day workflow.
- Edit campaign configuration (quotas, precinct metadata, users).
- View or modify data outside assigned precinct scope.
- Log supporter outreach outcomes from the polling-site workflow.

---

## Election-Day Workflow

## 1) Pre-open (setup)
- Confirm the correct completed GEC import is activated as the election-day voter list.
- Confirm watcher login works and assigned precincts are visible.
- Confirm polling site, precinct number, and registered voter baseline are correct.
- Confirm any explicit precinct assignments match the operations roster.
- Confirm escalation channel (war room lead contact) is known.

## 2) During polling (repeat cycle)
- Capture latest precinct turnout count.
- Submit a precinct report update (voter count + optional issue notes).
- Work strike list of registered voters in precinct:
  - mark `voted` when confirmed
  - leave/mark `not_yet_voted` when still pending
- Use campaign supporter overlay only as an indicator that War Room follow-up may be needed.
- War room operators, not poll watchers, log outreach outcomes for call/SMS/door attempts.
- Escalate blocking issues immediately (site disruption, data mismatch, etc.).

## 3) Closeout
- Submit final turnout snapshot for precinct.
- Ensure high-priority unresolved supporters are handed off to war room.
- Confirm no unsent local changes remain in app session.

---

## Data Events to Capture

## Precinct report event
- `precinct_id`
- `reported_at`
- `voter_count`
- `report_type` (`normal` or `issue`)
- `notes` (optional)
- `reported_by_user_id`

## Voter turnout event
- `gec_voter_id`
- `turnout_status` (`not_yet_voted`, `voted`, `unknown`)
- `updated_at`
- `updated_by_user_id`
- `source` (`poll_watcher`, `war_room`, `admin_override`)
- `note` (optional)

## Supporter outreach event
- `supporter_id`
- `outcome` (`attempted`, `reached`, `wrong_number`, `unavailable`, `refused`)
- `channel` (`call`, `sms`, `in_person`)
- `recorded_at`
- `recorded_by_user_id`
- `note` (optional)

Recorded by War Room / caller workflow, not by the polling-site watcher workflow.

---

## War Room Handoff Expectations

War room should be able to consume watcher updates immediately:

- Queue: campaign supporters with `not_yet_voted`, derived by overlaying supporter status on the full turnout-marked voter list
- Exception bucket: active approved supporters with no linked `gec_voter_id`, for manual matching or operator follow-up outside the derived queue
- Breakdowns: by village, precinct, and priority
- Counters:
  - remaining
  - attempted
  - reached
  - voted
- Escalation feed: precinct issue reports requiring coordinator action

---

## Guardrails and Compliance

- Strict precinct assignment scope for poll watchers (read and write).
- Full audit logging for turnout and outreach status changes:
  - actor
  - timestamp
  - from -> to values
  - source + note metadata (when present)
- Explicit UI label that turnout markers are campaign-tracked operational records.
- Explicit distinction between:
  - full-voter turnout marking
  - supporter-only outreach follow-up derived from that turnout data and handled by War Room

---

## Implementation Mapping (Execution Tracker Item 7)

- `7.1` Data model + migration:
  - Add full-voter turnout fields and supporter outreach logging schema.
- `7.2` Backend API:
  - Precinct-scoped full-voter strike-list fetch + turnout update endpoints for poll watchers.
  - War room outreach logging endpoints for matched supporters needing follow-up.
- `7.3` Audit + compliance:
  - Full change log and campaign-data disclaimers.
- `7.4` Poll watcher UI:
  - Mobile-first full-voter strike-list actions and rapid turnout toggles, with supporter overlay indicators.
- `7.5` War room queue integration:
  - Live not-yet-voted supporter queue and progress counters derived from full-voter turnout state.
- `7.6` Tests + QA:
  - Role/scope tests and election-day simulation checklist.
- `7.7` Rollout readiness:
  - Operator rehearsal and assignment validation.

---

## Open Questions to Confirm with Campaign Ops

- How often should watchers submit turnout snapshots (every X minutes vs event-driven)?
- Can multiple watchers be assigned to the same precinct, and if so, who wins conflicts?
- Which outreach outcomes are mandatory vs optional?
- What is the escalation SLA for precinct issues (immediate, 5 min, 15 min)?
- Do we need offline queueing for polling sites with weak connectivity in v1?
