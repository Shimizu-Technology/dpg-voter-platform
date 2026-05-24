# DPG Open Questions for Next Walkthrough

Last updated: May 24, 2026

Use this as the working question list for Auntie Stephanie, Mike Weekly, and the DPG beta testers. The goal is to avoid guessing DPG operating rules, especially around Election Day and official party lists.

## 1. Election Day / poll watcher rules

Current MVP assumption: poll watcher checkoff is based on the official GEC registered precinct. A DPG contact may keep a separate DPG contact village for outreach, but their Election Day voter row remains tied to the GEC precinct.

Questions to confirm:

1. **Official precinct vs DPG contact village**
   - If a person signs up with a Barrigada address but the GEC list says they are registered in Hagåtña, should poll watchers treat them as Hagåtña for Election Day checkoff?
   - Is it acceptable to show both contexts: official GEC village/precinct and DPG contact village/precinct?
   - Should the Barrigada poll watcher be able to find them only by search/out-of-precinct exception, or should they appear in Barrigada’s normal list too?

2. **Out-of-precinct voters at a polling site**
   - What should DPG poll watchers do if someone appears at a village/precinct where they are not registered?
   - Should poll watchers record a “Name Not On List” / exception report only?
   - Should anyone be allowed to mark that voter as voted from the wrong precinct, or should only admins/data coordinators reconcile those cases?
   - If cross-precinct voting is allowed in any official process, what exact status should the app use so it does not distort normal precinct turnout counts?

3. **Turnout counts**
   - Should aggregate turnout counts be based only on voters registered to that precinct?
   - Should out-of-precinct observations count in a separate exception/reconciliation metric?
   - Does DPG want poll watchers to submit individual voter checkoffs, aggregate counts, or both?

4. **Poll watcher visibility**
   - Should poll watchers see only GEC voter rows, or also linked DPG contact context?
   - Should poll watchers ever see phone/email/contact notes, or should those stay admin/field-organizer only?
   - Should poll watchers see DPG support/member/volunteer status, or only voter-list status?

5. **Corrections and audit trail**
   - Can poll watchers correct their own turnout marks?
   - Should corrections require a note?
   - Who can reconcile out-of-precinct exceptions after Election Day?

6. **Election Day dashboard language**
   - Should DPG call the admin dashboard “Election Day Dashboard,” “War Room,” “Command Center,” or something else?
   - What are the top dashboard metrics DPG wants: total GEC turnout, DPG supporters, registered Democrats, members, ride-to-polls, unresolved exceptions, or a combination?

## 2. DPG list samples needed

Do not build schema-specific importers until DPG provides real sample files or column headers. GEC import is the exception because we already have real GEC data formats.

Ask DPG for safe sample files or screenshots/column headers for:

1. Official DPG member roster
2. Registered Democrat list
3. Active party/contact list
4. Inactive party/contact list
5. Current supporter/contact list, if separate from active party list
6. Any precinct captain / village organizer list
7. Any poll watcher assignment list
8. Any ride-to-polls / voter assistance list
9. Any do-not-contact, deceased, moved, duplicate, or retention-rule list

For each list, ask:

- Who owns/maintains it?
- How often is it updated?
- Which columns are required?
- Which fields are trusted as official vs self-reported?
- Should rows ever be deleted, or only marked inactive/archived?
- Should it link to GEC voters, DPG contacts, or both?
- Who can import/export/view it?
- What should happen when the same person appears on multiple lists?

## 3. List cross-reference/reporting questions

1. How should the app distinguish:
   - DPG contact/supporter
   - official DPG member
   - registered Democrat
   - GEC registered voter
   - volunteer
   - inactive party record

2. What reports does DPG need first?
   - DPG contacts not on GEC
   - GEC voters not in DPG contacts
   - official members not matched to GEC
   - registered Democrats not in DPG contacts
   - DPG contacts with GEC address/village mismatches
   - supporter/member/registered-Democrat overlap
   - inactive records that reappear as new signups

3. What retention rules apply?
   - DPG confirmed active/inactive lists exist and have special handling.
   - Confirm whether inactive records should be preserved, hidden from active workflows, excluded from outreach, or used for duplicate detection only.

## 4. Current safe product stance

Until DPG answers the above:

- Poll watcher MVP should keep checkoff tied to official GEC precincts.
- DPG contact village should remain separate outreach context.
- Out-of-precinct search matches should be recorded as incidents/exceptions, not normal turnout by poll watchers.
- Admin/coordinator reconciliation can handle exceptions with audit logs.
- Official member/registered-Democrat/import workflows should remain pending real DPG list samples.
