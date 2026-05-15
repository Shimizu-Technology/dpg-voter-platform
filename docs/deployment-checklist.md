# DPG Deployment And QA Checklist

**Last updated:** May 14, 2026
**Current verified branch:** `feature/intake-relationship-household-polish`

## Current deployment status

The DPG app has been deployed online. This checklist now tracks what must be confirmed on the deployed environment before the app is treated as production-ready for broad DPG staff use.

The main remaining risk is not missing code for the current foundation. It is that most admin-side flows have not yet been thoroughly tested in a real deployed browser session with DPG auth, DPG database, DPG URLs, and DPG provider credentials.

## Environment isolation

- [x] GitHub repository is DPG-specific: `Shimizu-Technology/dpg-voter-platform`.
- [ ] Deployed backend service is confirmed DPG-specific and does not reuse the Josh/Tina service.
- [ ] Deployed frontend service is confirmed DPG-specific and does not reuse the Josh/Tina site.
- [ ] Backend service uses a DPG-specific `DATABASE_URL`.
- [ ] Backend service uses a DPG-specific `DIRECT_DATABASE_URL` for migration/pre-deploy commands.
- [ ] Render worker service is DPG-specific if background jobs run separately.
- [ ] `CACHE_DATABASE_URL` and `QUEUE_DATABASE_URL` are DPG-specific or intentionally blank to share the DPG `DATABASE_URL`.
- [ ] `SECRET_KEY_BASE` is set on backend web and worker services.
- [ ] `REDIS_URL` is blank for simple deploy or points to DPG-specific Redis if realtime is enabled.
- [ ] Frontend uses a DPG-specific Clerk publishable key.
- [ ] Backend uses a DPG-specific Clerk secret key.
- [ ] Netlify deploy uses the DPG-specific `NETLIFY_SITE_ID`.
- [ ] `FRONTEND_URL` points to the DPG frontend domain/subdomain.
- [ ] `ALLOWED_ORIGINS` includes only the DPG frontend domain(s).
- [ ] SMS sender settings are DPG-specific or explicitly approved shared infrastructure.
- [ ] Email sender/domain settings are DPG-specific or explicitly approved shared infrastructure.
- [ ] GEC import storage is DPG-specific. If `AWS_S3_BUCKET=dpg-voter-platform`, the configured AWS access key must have `s3:PutObject`, `s3:GetObject`, and `s3:DeleteObject` for `arn:aws:s3:::dpg-voter-platform/*`.
- [ ] Render is not using the campaign-tracker-only S3 IAM policy against the DPG bucket. The May 14 prod failure showed `campaign-tracker-s3` denied on `dpg-voter-platform`; code now falls back to database-backed upload storage, but IAM should still be corrected before routine imports.
- [ ] `DPG_LIVE_OUTREACH_ENABLED=true` is set only on the intended DPG environment after confirming SMS/email credentials.
- [ ] Database backups are configured before DPG enters real data.

## Domain status

- [ ] Current deployed URL/domain is documented.
- [ ] Confirm whether DPG wants to use an existing domain or a purchased domain.
- [ ] Once selected, configure the proper DPG domain and update `FRONTEND_URL`, `ALLOWED_ORIGINS`, Clerk allowed origins/redirects, and email links if needed.
- [ ] Keep the temporary/free deploy domain only as a staging/fallback URL after the official domain is active.

## CI and source verification

Latest merged Phase 5 PR passed:

- [x] `api_lint`
- [x] `api_scan_ruby`
- [x] `api_test`
- [x] `web_lint_build`
- [x] Greptile review

Latest local backend verification during Phase 5 review:

- [x] Rails tests passed: `197 runs, 748 assertions, 0 failures`.
- [x] RuboCop passed: `194 files inspected, no offenses`.
- [x] Bundler audit passed: no vulnerabilities.

Local repo note:

- [ ] Resolve or intentionally ignore the untracked root `package-lock.json` before the next commit/handoff.

## Deployed public smoke test

- [ ] Public landing page loads on deployed URL.
- [ ] DPG branding/logo/copy render correctly.
- [ ] Public signup page loads.
- [ ] Public signup submits a test contact.
- [ ] Thank-you page renders with DPG copy.
- [ ] Submitted public signup appears in Contacts.
- [ ] Submitted public signup appears in Intake / `new_intake`.
- [ ] Submitted public signup does not count as official supporter/member until classified.

## Deployed admin smoke test

These are the highest priority because the admin side has not yet been thoroughly browser-tested on the deployed environment.

- [ ] Admin login works with DPG Clerk app.
- [ ] Admin dashboard loads.
- [ ] Contacts list loads.
- [ ] Intake filter loads.
- [ ] Contact detail loads.
- [ ] Contact classification update saves and persists.
- [ ] Contact voter-help/support fields save and persist.
- [ ] Contact History timeline loads.
- [ ] Manual contact-attempt logging works.
- [ ] Manual Entry creates a DPG contact.
- [ ] Search/filter works by name, phone, email, village, precinct, and address text.
- [ ] Duplicate review page loads.
- [ ] Duplicate scan works on a small safe test set.
- [ ] Reports page loads.
- [ ] Reports preview works.
- [ ] Reports/export download works.
- [ ] Users page loads.
- [ ] User create/update works for a test staff user.
- [ ] Audit logs record deployed admin actions.

## Deployed import QA

- [ ] Contact import page loads.
- [ ] Small CSV/Excel contact import preview works.
- [ ] Import column mapping/parse works.
- [ ] Import confirm creates DPG contacts.
- [ ] Imported contacts default to `new_intake`.
- [ ] Imported contacts are searchable.
- [ ] Imported contacts appear in Intake until classified.

## Deployed GEC voter workspace QA

- [ ] GEC Voters page loads.
- [ ] GEC stats load.
- [ ] GEC import history loads.
- [ ] GEC import preview works with a small safe file.
- [ ] GEC upload works with a controlled test file.
- [ ] GEC import activation works only for intended imports.
- [ ] GEC search works by name.
- [ ] GEC search works by address.
- [ ] GEC search works by village/precinct.
- [ ] Create DPG contact from GEC voter works.
- [ ] Link existing DPG contact to GEC voter works.
- [ ] Linked contact appears correctly from GEC and contact detail views.

## Deployed household/outreach QA

- [ ] Households page loads.
- [ ] Address search returns GEC voters.
- [ ] Address search returns DPG contacts.
- [ ] Household view distinguishes GEC voters and DPG contacts.
- [ ] Follow-Up Queue loads.
- [ ] Latest contact attempt appears on queue cards.
- [ ] Queue-card call/SMS/in-person logging works.
- [ ] Queue-card logging updates the contact detail timeline.

## Deployed SMS/email QA

- [ ] SMS status page/API loads.
- [ ] SMS settings page loads.
- [ ] SMS blast page loads.
- [ ] SMS starter templates populate the message box.
- [ ] SMS dry-run returns recipient count and sample recipients.
- [ ] SMS live send is blocked unless recipient review/count confirmation is present.
- [ ] Controlled single-recipient SMS live test succeeds only when DPG approves.
- [ ] Email status page/API loads.
- [ ] Email blast page loads.
- [ ] Email starter templates populate subject/body.
- [ ] Email dry-run returns recipient count and sample recipients.
- [ ] Email live send is blocked unless recipient review/count confirmation is present.
- [ ] Controlled single-recipient email live test succeeds only when DPG approves.
- [ ] SMS/email blast attempts appear in Contact History.

## Handoff notes

- This is the DPG voter engagement platform, built from Shimizu Technology's reusable foundation.
- It excludes other campaign branding, data, operating playbooks, and proprietary campaign-specific workflows.
- DPG can begin guided familiarization once admin access is created.
- Do not describe the app as a finished Election Day command center yet.
- Live outreach is configured/gated, but real sends should only happen intentionally with approved recipients/content.
- Auntie Stephanie should be created as `campaign_admin` using her preferred email until DPG role names are polished.

## Known deferred modules

- Explicit DPG list types: DPG members, registered Democrat list, contacts/supporters, other/custom.
- DPG membership/supporter roster vs GEC cross-reference reports.
- DPG role-name cleanup and stricter export/delete permission rules.
- QR download/share/attribution workflow.
- Support/lean/donation tracking.
- DPG-defined district grouping.
- Advanced canvassing route/assignment tooling.
- Poll watcher workflow.
- Real-time voted/not-voted tracking.
- War-room/turnout dashboard.
- GIS/maps/heatmaps.
- ID/photo/OCR scanning.
- Autodialer integration.
