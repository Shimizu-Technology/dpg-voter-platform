# Monday Testing Handoff — Democratic Party of Guam

## Purpose

This app is the Democratic Party of Guam voter engagement platform. It is a DPG-specific deployment built from Shimizu Technology's reusable foundation, with other campaign branding, data, proprietary workflows, and election-day operating playbooks removed.

## What testers should focus on first

1. Public landing page and signup
2. Supporter/contact record creation
3. Admin login and user roles
4. Supporter/contact search and filtering
5. Manual staff entry
6. Small CSV import preview and confirm
7. Duplicate review
8. Voter-help follow-up flags
9. Reports/export basics
10. SMS/email outreach pages and settings visibility; preview/dry-run is safe, but live sending remains disabled unless `DPG_LIVE_OUTREACH_ENABLED=true` is explicitly approved

## Smoke test script

### Public signup
- Open the public site.
- Confirm DPG logo, title, and copy render correctly.
- Submit a test supporter with phone/email opt-in.
- Confirm the thank-you page uses DPG copy.

### Admin/data review
- Log into the DPG Clerk app as an admin/staff user.
- Confirm the supporter appears in the list.
- Open the supporter detail page.
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
- Verify records appear in the supporter list.

### Roles/settings
- Confirm Users/Roles page loads.
- Confirm Districts/Precincts page loads.
- Confirm SMS, Email, and SMS/Public Settings pages load.
- Run dry-run/preview only for SMS/email recipient counts.
- Do not send a live blast unless approved by Leon/DPG and the DPG sender/domain setup is confirmed.

## Known intentionally deferred modules

These are intentionally not part of Monday starter testing unless DPG separately scopes them:

- Election-day command center
- Poll-site observer operations
- QR/event check-in workflows
- Gamified quota/collection targets
- OCR/paper-form scanning
- Campaign-specific sign/parade workflows
- Other campaign's private methods or operating playbooks

## Success criteria for Monday

- DPG branding is clean across public/admin surfaces.
- Signup and core CRM flows work end-to-end.
- Test records persist in the isolated DPG database.
- Staff can search, edit, import, and export basic supporter/contact data.
- No other campaign names, assets, or proprietary workflows are visible.

## May 9 Clean-Room Cleanup Update

- Active yard-sign/follow-up flag surfaces were removed from staff entry, supporter lists, blast filters, and API payloads.
- Inherited election-day turnout display/API surfaces were hidden from the DPG Monday build until DPG defines its own turnout workflow.
- Duplicate merge no longer touches event RSVP records, avoiding the inherited event-model runtime risk.
- Remaining static `campaign-tracker` cache/routing metadata was renamed to DPG-specific keys.
