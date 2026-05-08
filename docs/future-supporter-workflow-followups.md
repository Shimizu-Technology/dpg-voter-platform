# Future Supporter Workflow Follow-Ups

This document tracks supporter-workflow ideas that are intentionally deferred so the current product stays clear and honest for staff.

## Remaining QA coverage

These areas are not considered blocked, but they still need a dedicated smoke test before final rollout:

- `Poll Watcher` role flows and election-day scoped permissions
- `War Room` dashboards and live-update behavior during election-day operations
- `SMS Blasts` creation, targeting, preview, and send permissions
- `Email Blasts` creation, targeting, preview, and send permissions
- `Events` creation, RSVP/check-in flows, and role-based access
- Any other campaign-day operational tools outside the supporter intake, review, dashboard, reports, quota, and core RBAC paths already tested

Suggested follow-up when time allows:

- Run one pass per role on the remaining operational tools
- Confirm permissions, navigation, and scoped data visibility
- Verify happy path plus one obvious denial path for each restricted feature
- Capture any production-readiness notes discovered during that pass

## Current product decisions

- `Accept to Supporter List` means the campaign wants to keep and work the supporter record.
- `Verified Voter` means the supporter has a current GEC voter-list match.
- `No GEC Match` means the supporter is not currently found in the latest GEC voter data.
- Staff should not be able to mark a `No GEC Match` supporter as a `Verified Voter`.

## Possible future enhancements

### Admin-only manual override

Potential future capability:

- Add an admin-only action for cases where staff has evidence outside the imported GEC file.
- This must NOT be named `Verified Voter`.
- Candidate labels:
  - `Manual registration override`
  - `Reviewed outside GEC list`
  - `Confirmed supporter, not found in GEC`

Requirements if implemented later:

- Separate from normal `Verified Voter`
- Strong warning text explaining it is not a GEC confirmation
- Admin-only permission
- Mandatory reason note
- Audit log entry with actor, timestamp, old value, new value, and reason

### Explain why voter check changed after a monthly GEC import

Potential future improvement:

- Show a clearer audit/event message when a supporter changes because a newer GEC file was imported.
- Example reasons:
  - `New monthly GEC list now matches this supporter`
  - `Supporter no longer appears in the latest GEC list`
  - `Supporter appears in a different village in the latest GEC list`

### Re-vetting progress visibility

Potential future improvement:

- If monthly GEC imports re-vet many supporters, show staff a summary in the import results:
  - supporters newly verified
  - supporters moved to needs review
  - supporters changed to no GEC match
  - supporters flagged as village referrals

### Distinguish campaign approval from outreach readiness

Potential future improvement:

- Add clearer messaging for when a supporter is accepted into the supporter list but still needs follow-up because they are not yet GEC-confirmed.
- This could eventually become a separate `reviewed supporter` or `ready for outreach` concept if staff needs it.
