# Monday Testing Handoff — Democratic Party of Guam

## Purpose

This app is the Democratic Party of Guam voter engagement platform. It is a DPG-specific deployment built from Shimizu Technology's reusable foundation, with other campaign branding, data, proprietary workflows, and election-day operating playbooks removed.

## Message frame for DPG

DPG can start clicking around now to get familiar with the foundation. The first pass should be treated as a working review build, not the final DPG workflow. They should try the signup, contacts, import, search, reports, roles, and outreach preview flows, then tell Leon where the flow should better match how the party actually works.

The strongest positioning is that the app is customizable for DPG. Because the system is built by Shimizu Technology rather than locked into an off-the-shelf product, labels, roles, reports, and workflows can be improved around DPG's real office and field process as they test it.

Updated product direction: the platform now centers on DPG contacts and a visible intake/classification workflow. Public signups, staff entries, and contact imports are visible immediately, but they do not count as official supporters/members until DPG classifies them. GEC voter-list import/search, address/household lookup, structured contact history, and deeper outreach follow-up are the next major implementation areas.

## What testers should focus on first

1. Public landing page and signup
2. Contact and intake record creation
3. Admin login and user roles
4. Contact search, intake, and filtering
5. Manual staff entry
6. Small CSV import preview and confirm
7. Duplicate review
8. Voter-help follow-up flags
9. Reports/export basics
10. SMS/email outreach pages and settings visibility; preview/dry-run first, with live sending configured for controlled DPG-approved sends

## Smoke test script

### Public signup
- Open the public site.
- Confirm DPG logo, title, and copy render correctly.
- Submit a test supporter with phone/email opt-in.
- Confirm the thank-you page uses DPG copy.

### Admin workspace review
- Log into the DPG Clerk app as an admin/staff user.
- Confirm the signup appears in Contacts and New Intake.
- Open the contact detail page.
- Change the classification from New Intake to a test classification such as Supporter, Member, Volunteer, or Active Contact.
- Add/update voter-help flags and a follow-up status.
- Save and refresh to confirm persistence.

### Manual entry
- Open staff/manual entry.
- Create one test supporter with a distinct name and phone number.
- Confirm duplicate warning behavior if the same contact is entered again.

### Import
- Upload a small test CSV with 2–5 rows.
- Preview mappings.
- Confirm import into DPG database.
- Verify records appear in Contacts and Intake.

### Roles/settings
- Confirm Users/Roles page loads.
- Confirm Districts/Precincts page loads.
- Confirm SMS, Email, and SMS/Public Settings pages load.
- Run dry-run/preview only for SMS/email recipient counts.
- Do not send a live blast unless approved by Leon/DPG and the DPG sender/domain setup is confirmed.

## Known intentionally deferred modules

These are intentionally not part of the starter testing build unless DPG separately scopes them:

- full GEC voter-list workspace
- household/address workspace
- structured contact attempt history
- Election Day command center
- poll-site observer operations
- QR/event attribution workflows
- OCR/paper-form scanning
- other campaign's private methods or operating playbooks

## Success criteria for Monday

- DPG branding is clean across public/admin surfaces.
- Signup and core CRM flows work end-to-end.
- Test records persist in the isolated DPG database.
- Staff can search, edit, classify, import, and export basic contact data.
- No other campaign names, assets, or proprietary workflows are visible.
- Stephanie has a `campaign_admin` account using her preferred email.

## May 9 Clean-Room Cleanup Update

- Active yard-sign/follow-up flag surfaces were removed from staff entry, supporter lists, blast filters, and API payloads.
- Inherited election-day turnout display/API surfaces were hidden from the DPG Monday build until DPG defines its own turnout workflow.
- Duplicate merge no longer touches event RSVP records, avoiding the inherited event-model runtime risk.
- Remaining static `campaign-tracker` cache/routing metadata was renamed to DPG-specific keys.

## May 11 Review Update

- Frontend lint passed.
- Frontend production build passed with only a local Node version warning from Vite.
- Rails tests passed with rbenv Ruby 3.3.7 and Bundler 4.0.5: 173 runs, 656 assertions, 0 failures.
- Local browser smoke test passed for landing, signup, and thank-you redirect. Staff/admin sign-in screens render; authenticated browser testing still needs a real Clerk user/session on staging.
- Added a DPG readiness integration smoke test covering the main public, admin/API, address/email search, import, report, and outreach dry-run paths.
- Current recommendation: share as a familiarization/testing foundation after confirming DPG staging/deploy isolation and creating Stephanie's admin user. The Phase 1 DPG workflow reset is implemented; next major build priority is the GEC voter-list/address workspace.
