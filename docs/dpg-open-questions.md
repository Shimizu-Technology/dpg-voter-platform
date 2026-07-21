# DPG Open Questions for Next Walkthrough

Last updated: May 24, 2026

Use this as the working question list for Auntie Stephanie, Mike Weakley, and the DPG beta testers. The goal is to avoid guessing DPG operating rules, especially around Election Day, official party lists, and the distinction between DPG contact geography and official GEC registration geography.

## 1. Election Day / poll watcher rules

Current MVP assumption: poll watcher checkoff is based on the official GEC registered precinct. A DPG contact may keep a separate DPG contact village for outreach, but their Election Day voter row remains tied to the GEC precinct.

### GEC manual notes found during research

Source reviewed: Guam Election Commission Election Manual linked from `https://gec.guam.gov/` as the “ELECTION MANUAL” Google Drive resource, downloaded May 24, 2026.

Relevant manual guidance:

- Poll watchers are observers for recognized political parties/candidates. Their duties include observing the conduct of the election, issuing voter challenges, and monitoring voter participation.
- Poll watchers are prohibited from interfering with the precinct board, entering the voting area/barricade, accessing the official voter signature roster or other official voter documents, asking voters for ID, speaking to voters about marking ballots, or campaigning/wearing campaign identifiers.
- Poll watcher areas are designated by precinct leadership and must be separated from the voting area/ballot boxes.
- If a person is not on the precinct signature roster or appears to be at the wrong polling location, precinct officials must make efforts to determine registration status and correct polling location, including checking precinct/polling-area lists and contacting GEC headquarters. Those situations may become provisional-ballot workflows handled by precinct officials/GEC, not by party poll watchers.
- Challenge grounds include whether the person is not a resident of the precinct where they are voting, has voted that day, voted in another precinct, or voted in another U.S. jurisdiction.

Product interpretation until DPG/Mike Weakley confirms otherwise:

- Treat poll watchers as limited DPG operations observers/checkoff users, not election officials.
- Keep “DPG operations tracking only; not official election records” language visible.
- Do not let normal poll watchers directly mark out-of-precinct voters as regular voted records.
- Record out-of-precinct or name-not-on-list situations as incidents/exceptions for admin/coordinator reconciliation.

Questions to confirm:

1. **Official precinct vs DPG contact village**
   - If a person signs up with a Barrigada address but the GEC list says they are registered in Hagåtña, should poll watchers treat them as Hagåtña for Election Day checkoff? Current safest answer: yes.
   - Is it acceptable to show both contexts: official GEC village/precinct and DPG contact village/precinct? Current product recommendation: yes, show both clearly instead of merging them.
   - Should the Barrigada poll watcher be able to find them only by search/out-of-precinct exception, or should they appear in Barrigada’s normal list too? Current safest answer: search/exception only, not the normal Barrigada strike list.
   - Should DPG outreach/dashboards continue to count that contact under their self-reported/contact village for organizing purposes, while Election Day turnout/checkoff counts use GEC village/precinct? Current recommendation: yes, but make the distinction more explicit in UI labels/reports.

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

6. **Election event setup / repeat elections**
   - Should DPG create a separate election event for each election, such as August primary and November general, so turnout counts reset cleanly?
   - What should DPG call this in the app: Election Event, Election Day Setup, Primary Election, General Election, or something else?
   - Who can create, activate, close, or archive an election event?
   - Should each election require selecting the exact GEC import/list date used by poll watchers?
   - If DPG imports a newer GEC list after training or after checkoff begins, who can switch the election to the newer list, and what confirmation/audit should be required?
   - Should training/test turnout be isolated in a training election or resettable before the real election opens?

7. **Election Day dashboard / command center language**
   - Should DPG call the admin dashboard “Election Day Dashboard,” “War Room,” “Command Center,” or something else?
   - What are the top dashboard metrics DPG wants: total GEC turnout, DPG supporters, registered Democrats, members, ride-to-polls, unresolved exceptions, contacted/not-contacted not-yet-voted voters, or a combination?
   - Should admins be able to drill from village to precinct to a list of voted/not-yet-voted voters?
   - Should the command center include an inline call/text queue for linked DPG contacts who have not yet voted?
   - What Election Day follow-up outcomes should be tracked: plans to vote, needs ride, already voted, unreachable, wrong number, refused, do-not-contact?

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

3. **Contact village vs GEC registered village in normal site reports**
   - Current app behavior: Contacts/Dashboard/organizing reports generally group DPG contacts by the address/village they signed up with or staff entered, while Poll Watcher strike lists group voters by official GEC precinct/village.
   - Is this the right operating model for DPG? Current product recommendation: yes, but the UI should label it clearly as “DPG contact village” or “Signup/contact village” versus “Official GEC registered village/precinct.”
   - Should dashboard cards and report exports include both fields where available so staff understand why a person can be a Barrigada DPG contact but a Hagåtña Election Day voter?
   - Should there be a dedicated “DPG/GEC village mismatch” report or saved filter for cleanup and planning?
   - Should village coordinators be assigned by DPG contact village, GEC registered village, or both depending on workflow?

4. What retention rules apply?
   - DPG confirmed active/inactive lists exist and have special handling.
   - Confirm whether inactive records should be preserved, hidden from active workflows, excluded from outreach, or used for duplicate detection only.

## 4. Current safe product stance

Until DPG answers the above:

- Poll watcher MVP should keep checkoff tied to official GEC precincts.
- DPG contact village should remain separate outreach/organizing context.
- Normal dashboard/contact reports may continue grouping by DPG contact village, but labels should be explicit when GEC village/precinct is different.
- Out-of-precinct search matches should be recorded as incidents/exceptions, not normal turnout by poll watchers.
- Admin/coordinator reconciliation can handle exceptions with audit logs.
- The next full Election Day build should add explicit election events and election-scoped turnout so August/November or future elections do not share counts.
- Poll Watcher and Command Center should use the GEC import/list attached to the active election, not silently use stale or ambiguous data.
- Official member/registered-Democrat/import workflows should remain pending real DPG list samples.
