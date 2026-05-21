# DPG Demo Debrief - May 20, 2026

**Meeting:** Live app walkthrough with Auntie Stephanie and DPG team  
**Source transcript:** `Brain-Dump/work/shimizu-tech/Democratic-Party/3) Demoing app with the Democratic Party.md`  
**Status:** Successful beta-validation demo; DPG is ready to test with real users and provide feedback/list samples.

## Executive summary

The walkthrough went well. DPG understood the app quickly and moved from evaluating the concept to discussing how they would use it operationally: public signups, Intake, GEC lookup/linking, household/PO-box search, QR signup links, duplicate cleanup, SMS/email outreach, quotas/periods, and Election Day poll-watcher workflows.

The strongest validation was that Auntie Stephanie described the platform as better aligned to DPG's Guam-specific needs than national tooling like VoteBuilder, because the app maps to villages, precincts, PO boxes, family groups, local list realities, and DPG's own organizing process.

The meeting changed the project posture from "guided review build" to "controlled beta with DPG testers." The next work should be driven by the friction and requests from this demo, not speculative campaign-clone features.

## What landed well

### Public signup and Intake

DPG understood the public-signup flow and the Intake bucket concept:

- public signup creates a record immediately
- staff reviews/classifies it before it becomes an approved DPG contact
- staff can approve, reject/classify as duplicate, set support/volunteer status, and link to GEC

The intake model was validated as a safer party-operations workflow than automatically treating every signup as a real supporter/contact.

### GEC voter import/search/linking

The team liked that GEC data can be uploaded, versioned, searched, and linked to DPG contacts. They understood the value of:

- comparing DPG-entered data to official GEC data
- seeing possible GEC matches
- confirming a link from contact to GEC voter
- tracking who imported a file and what changed between imports

This remains a core DPG-specific foundation.

### Household/address lookup

Household search resonated strongly because Guam addressing is messy and family/PO-box grouping matters. The team used real examples during the meeting and saw value in finding:

- who appears at an address according to GEC
- which GEC voters are already DPG contacts
- family groups sharing mailing addresses
- stale or incorrect GEC addresses

Auntie Stephanie explicitly noted that PO-box/family grouping may not make sense to outsiders but does make sense for DPG's Guam context.

### QR/signup-link attribution

The team immediately understood QR/signup links as an organizing tool:

- each person/village/outreach push can have a link or QR code
- signups can be credited back to that source
- DPG can run sign-up contests or incentives
- Young Democrats and village organizers can share links easily

This feature is likely to be used in beta.

### Duplicate Contact Review

Duplicate cleanup was validated by a real pain point: multiple people may enter the same contacts into different quota or village lists. The Duplicates workflow directly addresses the concern that one person may be entered more than once by different organizers.

### Reports and exports

Reports were understood as useful for follow-up and cleanup, especially lists like contacts who are not yet supporters, GEC/contact cross-reference lists, and referral-style cleanup.

### Mobile-friendly internal use

DPG recognized that mobile support matters for canvassing and poll-watching. The app should continue to be designed mobile-first.

## Main issues and findings from the demo

### 1. GEC search was too strict

This was the biggest live-demo friction.

Observed issue:

- `Christopher C Flores` and `Christopher C. Flores` did not behave equivalently.
- Middle initials and periods made search too strict.
- Some people did not appear as expected until the query was adjusted.

Desired behavior:

- punctuation-insensitive name search
- middle-initial tolerant matching
- `C`, `C.`, and omitted middle punctuation should still return likely candidates
- broader search is preferable to hiding valid matches

This should be the top immediate polish item.

### 2. Address search/normalization needs to be more forgiving

The meeting surfaced common Guam address realities:

- PO Box / P.O. Box / box variants
- HCR/HC route boxes
- stale GEC mailing addresses
- family members sharing addresses
- official GEC addresses not matching what people currently use

Desired behavior:

- address search should normalize punctuation, abbreviations, and PO-box/HCR variants
- similar addresses should be discoverable even when typed differently
- address/household search should help staff find likely matches, not require exact formatting

### 3. GEC list view search may have a bug or overly strict matching

During the demo, the GEC list view did not always pull up expected people cleanly. This may be related to strict punctuation/middle-name matching, but it should be verified specifically in the GEC voters page.

Needed investigation:

- search query normalization
- first/middle/last-name parsing
- punctuation handling
- whether address and name filters interact too narrowly
- whether current GEC imported data is old/stale versus search malfunction

### 4. SMS status and resend-to-failed are needed

DPG asked whether they can see who did and did not receive SMS messages.

Requested capability:

- show per-recipient delivery status
- distinguish sent/delivered/failed/pending if provider supports it
- resend only to people who did not receive or failed
- avoid blasting everyone again and annoying people

This is a clear roadmap item, but likely larger than simple UI polish because it depends on SMS provider delivery status storage and/or callbacks.

### 5. QR code downloads are needed

Current signup links can be copied and displayed, but DPG will need to reuse QR codes in other places.

Requested capability:

- download QR code as PNG/SVG
- possibly later generate simple printable cards/flyers

This is likely a quick, high-value beta polish item.

### 6. Signup links need delete/archive lifecycle

DPG should be able to clean up unused signup links.

Recommended behavior:

- if a signup link has zero signups: allow delete
- if a signup link has signups: archive/deactivate instead of hard delete so attribution history stays intact
- inactive/archived links should not be usable for new attribution

### 7. Safe demo/contact cleanup is important

Because some production data was entered during the demo, we need to ensure cleanup does not harm future legitimate signups.

Requirement:

- removing/archiving/disabling a contact should not prevent that person from signing up again later
- future signups should still be trackable and should enter Intake normally
- archived/removed records should not create incorrect duplicate blockers
- dismissed duplicate-pair history should only apply to exact record pairs, not future new records

This should have regression coverage.

### 8. Quotas/periods are now DPG-requested

Quota/period workflows were previously avoided because they could have copied another campaign's operating model. After this meeting, DPG independently raised quota/period needs in their own context.

DPG need:

- define a period/cycle such as a month, quota period, or outreach push
- signups/contacts during that period count toward the active period
- when the next period starts, new signups/contacts count toward the new period, not the old one
- village/team/source totals should be reportable by period
- duplicate handling should prevent double-counting the same person across lists/periods

This should be designed as a DPG-owned goals/period system, not copied from Josh/Tina.

### 9. DPG list imports are real but need sample files

DPG confirmed they have active and inactive party lists and specific membership rules.

Important context:

- active list exists
- inactive list exists
- DPG cannot casually purge membership records
- official party membership/list logic has special rules

Next step is to obtain real sample files/columns before building official member roster or registered Democrat import flows.

### 10. Election Day / poll-watcher workflow is Phase 2

Auntie Stephanie clearly described the Election Day need:

- primary is August 1
- training should happen at least a week before election day
- Mike Weekly should be involved
- poll watchers need to mark voters as voted by precinct
- DPG needs a dashboard/war-room view of who has voted

This should be scoped as a dedicated Phase 2 module after beta polish and list/sample intake.

## Recommended next implementation sequence

### PR 1 - GEC search and beta usability polish

Highest priority because it directly affected the live demo.

Include:

- punctuation-insensitive GEC name search
- middle-initial tolerant search
- less strict GEC list view search
- address search normalization improvements
- QR code download for signup links
- signup link delete/archive behavior
- safe archive/remove contact and re-signup regression tests

### PR 2 - DPG quota/period foundation

Build only the DPG-owned period/goal primitives DPG requested.

Include:

- quota/period model
- active period selection
- assign new signup/contact attribution to active period
- period filters/counts on signup links and reports
- basic admin UI for periods/goals

Clarify before building detailed dashboards:

- quotas by village, user, signup link, or all of the above?
- count raw signups or approved contacts?
- how duplicates should affect period counts?

### PR 3 - SMS delivery status and resend

Larger integration task.

Include:

- per-recipient SMS status storage
- provider status polling/webhook support if available
- blast detail recipient table
- resend only failed/undelivered
- clear copy to avoid duplicate blasting

### Phase 2 - Election Day / poll watcher module

Coordinate with Auntie Stephanie and Mike Weekly.

Include:

- precinct-scoped poll watcher users
- mobile voter lookup by precinct
- mark voter as voted
- real-time turnout dashboard
- training flow before August 1

## Open questions

1. What are the actual columns in DPG's active and inactive membership/list files?
2. Who should be beta testers and what roles should they get?
3. What should the app/domain/name be long-term?
4. Should QR signup attribution count raw signups, approved contacts, or both?
5. What exactly defines a quota period for DPG: calendar month, pay period, outreach push, primary cycle, or custom date range?
6. How should inactive/archived contacts participate in future duplicate detection?
7. What delivery states can the current SMS provider expose reliably?
8. What does Mike Weekly need for poll-watcher training and Election Day operations?

## Product conclusion

The demo validated the app as a DPG operations platform, not just a reskinned campaign tracker. DPG's feedback centered on Guam-specific search, addresses, QR attribution, list management, duplicate cleanup, quotas/periods, SMS reliability, and poll-watcher readiness. The next work should focus on controlled beta polish and real DPG data/list samples before broad rollout.
