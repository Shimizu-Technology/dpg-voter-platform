# Election-Day Strike List Simulation Checklist

Last updated: 2026-04-20

Goal: run one full simulation from poll watcher updates to war-room queue response.

---

## Preconditions

- API and web apps running locally or in staging.
- Synthetic data seeded (recommended: 10k or 30k supporters).
- A completed GEC import is activated as the election-day voter list.
- At least one user account for each role:
  - `poll_watcher`
  - `campaign_admin` (or `district_coordinator`)
  - `block_leader` (negative access check)
- Poll watcher has explicit precinct assignments configured for the rehearsal, or assigned-village fallback is intentionally documented.

---

## Phase 1: Poll Watcher Field Actions

1. Sign in as `poll_watcher`, open `/admin/poll-watcher`.
2. Select an assigned precinct.
3. Submit a turnout report with `voter_count` and optional note.
4. In strike-list panel:
   - confirm full GEC voters appear, including at least one voter with no supporter overlay
   - mark one matched supporter/voter as `Not Yet Voted`
   - mark one matched supporter/voter as `Voted`
   - mark one non-supporter voter as `Voted`
5. Confirm success messages appear and voter cards reflect turnout and overlay changes.

Pass if updates save without errors and UI states update correctly.

---

## Phase 2: Scope and Permission Guards

1. While still `poll_watcher`, verify only assigned precinct voters are visible.
2. Sign in as different-scope watcher/chief/coordinator and confirm out-of-scope precinct requests are blocked.
3. Sign in as `block_leader` and open `/admin/poll-watcher` and `/admin/war-room`.
4. Confirm restricted actions/routes are blocked as expected.

Pass if unauthorized scope/actions consistently return denied behavior.

---

## Phase 3: War Room Queue Response

1. Sign in as `campaign_admin` (or `district_coordinator`) and open `/admin/war-room`.
2. Confirm these update after poll-watcher actions:
   - `Not Yet Voted` total
   - `Attempted` total
   - `Reached` total
3. Log one contact attempt as `Call Attempted` and one as `Reached` from the `Supporters To Call` panel.
4. Confirm `Not Yet Voted Queue` panel includes expected villages and pending counts.
5. Confirm `Supporters To Call` includes matched supporters whose linked GEC voters are still `not_yet_voted`.
6. Confirm `Unmatched Supporters` shows approved active supporters with no linked GEC voter and does not mix them into the matched queue.
7. Confirm village cards display:
   - `not_yet_voted_count`
   - `outreach_attempted_count`
   - `outreach_reached_count`
8. Refresh once and confirm values remain consistent.

Pass if war-room queue metrics reflect strike-list operations.

---

## Phase 4: Audit and Compliance Checks

1. Verify turnout changes emit audit entries with:
   - action `turnout_updated`
   - actor user
   - field-level `from -> to` values
2. Verify contact attempts emit audit entries with:
   - action `created`
   - outcome/channel/recorded_at payload
3. Confirm compliance text is visible in strike-list UI:
   - "Campaign operations tracking only; not official election records."

Pass if all critical changes are auditable and compliance context is visible.

---

## Evidence to Capture

- Environment and dataset size used.
- Role accounts used for each phase.
- Pass/fail per phase.
- Blocking defects with repro steps.
- Optional screenshots for queue panel and strike-list updates.

---

## Sign-Off

- Simulation status: Pass / Fail
- Blocking defects:
- Non-blocking defects:
- Recommended follow-up fixes:
