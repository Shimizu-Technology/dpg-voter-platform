# DPG Tester Handoff

> Historical filename note: this used to be the Monday testing handoff. The deployed app has moved past that first Monday scope, so this file is now the general DPG tester handoff.

## Purpose

This app is the Democratic Party of Guam voter engagement platform. It is a DPG-specific deployment built from Shimizu Technology's reusable foundation, with other campaign branding, data, proprietary workflows, and election-day operating playbooks removed.

## Message frame for DPG

DPG can start clicking around now to get familiar with the foundation. Leon has already completed an initial production QA pass, and Auntie Stephanie has access and confirmed it. The current build should still be treated as a guided review build, not the final DPG operating workflow.

The strongest message is that the app is customizable for DPG. Because the system is built by Shimizu Technology instead of locked into an off-the-shelf product, labels, roles, reports, and workflows can be improved around DPG's real office and field process as they test it.

Be clear that the deployed app has had an initial technical QA pass, but not the full DPG workflow validation pass. We should walk DPG through it, watch where the workflow feels confusing, and then tune the system around them.

## What is ready for familiarization

Testers can review:

1. Public landing page and signup
2. Admin login
3. Contacts list
4. Intake/new contact classification
5. Contact detail editing
6. Contact History timeline
7. Contact History correction by Administrator/Data Manager, with audit logging
8. Manual staff entry
9. Contact import preview/confirm
10. Duplicate review
11. GEC Voter List search/import workspace
12. Possible GEC match review before confirmation
13. Create/link DPG contacts from GEC voters
14. Household/address search
15. Household canvass logging and address normalization behavior
16. QR/signup-link attribution, active toggles, and per-link signup lists
17. Follow-Up Queue
18. Queue-card contact logging and follow-up status updates
19. Reports/export basics and DPG/GEC cross-reference reports
20. Users/roles
21. Audit logs
22. SMS/email dry-run recipient previews

Live SMS/email sends should only be tested with controlled DPG-approved recipients/content.

## What testers should not assume is final

- Database role values still use legacy internal names, but the UI now shows DPG-facing labels: Administrator, Data Manager, Field Organizer, Village Coordinator, and Canvasser.
- Explicit DPG member/registered-Democrat/supporter list types are not finished.
- DPG/GEC contact cross-reference reports are implemented; official member-roster and registered-Democrat list-lineage reports still need real DPG list samples.
- Support/lean/donation tracking is not finished.
- QR/share attribution is implemented; print-ready/downloadable QR assets are not finished.
- Election Day, poll watcher, turnout, and war-room workflows are not built yet.
- Maps/GIS, autodialer, OCR, and ID/photo intake are later add-ons.

## Smoke test script

### Public signup

- Open the public site.
- Confirm DPG logo, title, and copy render correctly.
- Submit a test contact with phone/email opt-in.
- Confirm the thank-you page uses DPG copy.
- In admin, confirm the signup appears in Contacts and Intake.

### Admin workspace

- Log into the DPG Clerk app as an admin/staff user.
- Confirm Dashboard loads.
- Open Contacts.
- Open Intake.
- Search for the test signup by name, phone, email, and address if available.
- Open the contact detail page.
- Change record status, support status, and volunteer interest.
- Save and refresh to confirm persistence.
- For a possible GEC match, open the contact and confirm the candidate shown before marking the person matched to GEC.

### Contact history

- Open a contact detail page.
- Add a test contact attempt:
  - channel: call, SMS, or in-person
  - outcome: reached, attempted, unavailable, or needs follow-up
  - note
  - timestamp
- Confirm the attempt appears in the timeline.
- If logged in as Administrator/Data Manager, edit a test contact attempt.
- Confirm the correction is saved and the Audit History records the change.

### Manual entry

- Open New Entry.
- Create one test contact with a distinct name and phone number.
- Confirm duplicate warning behavior if the same contact is entered again.
- Confirm the new contact appears in Contacts and Intake.

### Contact import

- Upload a small CSV/Excel file with 2-5 fake rows.
- Preview mappings.
- Confirm import.
- Verify records appear in Contacts and Intake.

### GEC voter workspace

- Open GEC Voters.
- Search by name.
- Search by address.
- Search by village/precinct.
- If using a safe test import file, preview/upload/activate a GEC import.
- Create a DPG contact from a GEC voter.
- Link an existing DPG contact to a GEC voter.

### Households

- Open Households.
- Search a test address.
- Confirm the page shows GEC voters and DPG contacts separately.
- Open related contacts and confirm links behave as expected.
- Try address variants such as `123 Chalan Example`, `123 Chalan Example Rd`, and the same street with the village included.
- Confirm obvious street suffix/locality variants group more cleanly without hiding the original entered address on the contact.
- Log a household canvass update on a safe test contact and confirm the Contact History timeline updates.

### Follow-Up Queue

- Open Follow-Up.
- Confirm queue cards show latest contact attempts when present.
- Log a call/SMS/in-person attempt from a queue card.
- Confirm the contact detail timeline updates.
- Confirm untouched registration or voter-help follow-up lanes move from "no outcome/progress set" to "started" after the first real contact attempt, while the final task outcome still requires a follow-up status update.

### Roles/settings

- Confirm Users page loads.
- Confirm the role matrix uses DPG-facing labels and explains what each role can do.
- Confirm a test user can be created/updated if appropriate.
- Confirm Districts and Precincts pages load.
- Confirm SMS/Public Settings page loads.
- Confirm audit logs capture changes.

### SMS/email

- Open SMS Blasts.
- Try starter templates.
- Run dry-run preview and inspect recipient count/sample.
- Confirm live send is blocked until recipient review/count confirmation is present.
- Open Email Blasts and repeat the same dry-run flow.
- Do not send a live blast unless approved by Leon/DPG and using a controlled recipient set.

## Success criteria for the current deployed QA pass

- DPG branding is clean across public/admin surfaces.
- Public signup and core CRM flows work end-to-end.
- Test records persist in the DPG database.
- Staff can search, edit, classify, import, and export basic contact data.
- GEC search/link/create-contact flows work on deployed admin.
- Household/address search works.
- Contact-history logging works from detail and Follow-Up Queue.
- SMS/email dry-run governance works.
- No other campaign names, assets, or proprietary workflows are visible.
- Auntie Stephanie has access and confirmed it.
- The UI uses the DPG-facing Administrator label for the highest-access role.

## Recommended feedback request to DPG

Ask testers to send:

- anything confusing
- anything that feels unnecessary
- anything that uses the wrong DPG language
- places where the workflow does not match how staff actually work
- reports they wish they had
- fields/statuses they need for supporters, official member-roster cross-reference, registered Democrats, or voter outreach
- what role/access levels they expect for office staff, field organizers, canvassers, and later poll watchers

## Known deferred modules

- Explicit list types for official DPG member rosters, registered Democrats, supporters/contacts, and other custom lists.
- Official member-roster and registered-Democrat list-lineage reports after DPG provides real list samples.
- Support/lean/donation tracking.
- Print-ready/downloadable QR assets beyond the current QR/share-link attribution workflow.
- Advanced canvassing route/assignment tooling.
- Election Day command center.
- Poll-site observer operations.
- Real-time voted/not-voted tracking.
- Turnout/war-room dashboard.
- Maps/GIS/heatmaps.
- OCR/paper-form scanning.
- ID/photo intake.
- Autodialer integration.

## Latest implementation status

- Phase 1 DPG workflow reset is merged.
- Phase 2 GEC Voter List workspace is merged.
- Phase 3 contact history and household workspace is merged.
- QR/share-link attribution is merged.
- Role/permission polish is merged.
- Contact-attempt correction, address normalization, GEC candidate review, and follow-up status sync are merged.
- Outreach queue latest-attempt display and inline logging are merged.
- Communications governance for SMS/email blasts is merged.
- The next recommended product phase is guided DPG workflow review plus real list-sample collection, then explicit list types and roster/registered-Democrat list-lineage reporting.
