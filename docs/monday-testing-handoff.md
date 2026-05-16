# DPG Tester Handoff

> Historical filename note: this used to be the Monday testing handoff. The deployed app has moved past that first Monday scope, so this file is now the general DPG tester handoff.

## Purpose

This app is the Democratic Party of Guam voter engagement platform. It is a DPG-specific deployment built from Shimizu Technology's reusable foundation, with other campaign branding, data, proprietary workflows, and election-day operating playbooks removed.

## Message frame for DPG

DPG can start clicking around now to get familiar with the foundation. The current build should be treated as a guided review and QA build, not the final DPG operating workflow.

The strongest message is that the app is customizable for DPG. Because the system is built by Shimizu Technology instead of locked into an off-the-shelf product, labels, roles, reports, and workflows can be improved around DPG's real office and field process as they test it.

Be clear that the deployed app has not yet had a full admin-side browser smoke test. We should walk DPG through it, watch where the workflow feels confusing, and then tune the system around them.

## What is ready for familiarization

Testers can review:

1. Public landing page and signup
2. Admin login
3. Contacts list
4. Intake/new contact classification
5. Contact detail editing
6. Contact History timeline
7. Manual staff entry
8. Contact import preview/confirm
9. Duplicate review
10. GEC Voter List search/import workspace
11. Create/link DPG contacts from GEC voters
12. Household/address search
13. Follow-Up Queue
14. Queue-card contact logging
15. Reports/export basics
16. Users/roles
17. Audit logs
18. SMS/email dry-run recipient previews

Live SMS/email sends should only be tested with controlled DPG-approved recipients/content.

## What testers should not assume is final

- Role names still use some inherited labels, such as `campaign_admin`.
- Explicit DPG member/registered-Democrat/supporter list types are not finished.
- DPG/GEC cross-reference reports are not finished.
- Support/lean/donation tracking is not finished.
- QR download/share attribution is not finished.
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
- Change classification from New Intake to Supporter, Member, Volunteer, or Active Contact.
- Save and refresh to confirm persistence.

### Contact history

- Open a contact detail page.
- Add a test contact attempt:
  - channel: call, SMS, or in-person
  - outcome: reached, attempted, unavailable, or needs follow-up
  - note
  - timestamp
- Confirm the attempt appears in the timeline.

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

### Follow-Up Queue

- Open Follow-Up.
- Confirm queue cards show latest contact attempts when present.
- Log a call/SMS/in-person attempt from a queue card.
- Confirm the contact detail timeline updates.

### Roles/settings

- Confirm Users page loads.
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
- Auntie Stephanie has a `campaign_admin` account using her preferred email.

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
- DPG/GEC cross-reference reports.
- Support/lean/donation tracking.
- Print-ready/downloadable QR assets beyond the current QR/share-link attribution workflow.
- DPG role-name cleanup and permission polish.
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
- Outreach queue latest-attempt display and inline logging are merged.
- Communications governance for SMS/email blasts is merged.
- The next recommended product phase is explicit list types plus DPG/GEC cross-reference reporting, after deployed admin QA.
