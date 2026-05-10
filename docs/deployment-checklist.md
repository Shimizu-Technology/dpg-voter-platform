# DPG Deployment Checklist

**Last updated:** May 9, 2026
**Current verified commit:** `0c532f4 DPG-17: Document current project status`

## Isolation requirements

- [x] GitHub repository is DPG-specific: `Shimizu-Technology/dpg-voter-platform`.
- [ ] Backend service uses a DPG-specific `DATABASE_URL`.
- [ ] Backend service uses a DPG-specific `DIRECT_DATABASE_URL` for migration/pre-deploy commands, matching the campaign-tracker production pattern.
- [ ] Render web service is DPG-specific and does not reuse the Josh/Tina service.
- [ ] Render worker service is DPG-specific if background jobs are run separately (`bundle exec bin/jobs`).
- [ ] `CACHE_DATABASE_URL` and `QUEUE_DATABASE_URL` are either DPG-specific Neon URLs or intentionally blank to share the DPG `DATABASE_URL`.
- [ ] `SECRET_KEY_BASE` is set on the Render web service and worker.
- [ ] `REDIS_URL` is blank for the simple Monday deploy, or points to DPG-specific Redis if shared realtime is needed.
- [ ] Frontend service uses a DPG-specific Clerk publishable key.
- [ ] Backend service uses a DPG-specific Clerk secret key.
- [ ] Netlify deploy uses a DPG-specific `NETLIFY_SITE_ID`.
- [ ] `FRONTEND_URL` points to the DPG frontend domain/subdomain.
- [ ] `ALLOWED_ORIGINS` includes only the DPG frontend domain(s).
- [ ] SMS/email sender settings are DPG-specific or explicitly approved shared infrastructure.
- [ ] `DPG_LIVE_OUTREACH_ENABLED=false` for Monday testing unless live sends are explicitly approved.
- [ ] Backups are configured for the DPG database before Monday testing.

## Pre-deploy verification

Verified locally after latest cleanup:

- [x] `npm --prefix web run lint`
- [x] `npm --prefix web run build`
- [x] `cd web && npx tsc -b --pretty false`
- [x] Ruby syntax checks for edited backend files.
- [x] `RAILS_ENV=test bundle exec rails zeitwerk:check`
- [x] `RAILS_ENV=test bundle exec rails db:prepare`
- [x] Render pre-deploy command uses `DATABASE_URL=$DIRECT_DATABASE_URL bundle exec rails db:migrate:primary` only after `DIRECT_DATABASE_URL` is set.
- [x] Background worker recurring tasks only reference classes that exist in the DPG build.
- [x] Source scan has no active Josh/Tina/quota/war-room/poll-watcher/yard-sign/event-rsvp residue in Monday-facing source.
- [x] Built `web/dist` scan has no other-campaign or proprietary workflow terms.
- [x] Rails route scan has no deferred election-day/proprietary modules. Only duplicate-review `scan_duplicates` remains, which is expected.

## Monday testing scope

Already smoke-tested locally:

- [x] Public signup submits a supporter/contact.
- [x] Thank-you page renders after signup.
- [x] Admin login works locally.
- [x] Supporter/contact list loads.
- [x] Supporter/contact detail loads.
- [x] Manual entry works.
- [x] Staff-entered supporters appear in search/list.
- [x] Import confirm works through authenticated API with a small test CSV.
- [x] Duplicate review API/page loads.
- [x] Reports API and supporter summary preview load.
- [x] Users/roles screen/API loads.
- [x] Audit logs load.
- [x] SMS/email pages render safely.
- [x] SMS/email dry-run works.
- [x] Live SMS/email blasts are blocked unless explicitly enabled.

Still needs staging verification:

- [ ] Public landing page loads with DPG branding on deployed frontend.
- [ ] Public signup submits a supporter/contact on staging.
- [ ] Admin login works with DPG Clerk app.
- [ ] Manual entry works on staging.
- [ ] Browser UI import upload/preview/confirm works on staging.
- [ ] Duplicate review works on staging.
- [ ] Reports/export downloads from staging.
- [ ] Users/roles mutations work with DPG Clerk users.
- [ ] Audit logs capture staging actions.
- [ ] SMS/email settings render safely on staging.
- [ ] Live blasts remain disabled unless Leon/DPG explicitly approves enabling them.

## Handoff notes

- This is the DPG voter engagement platform, built from Shimizu Technology's reusable foundation.
- It excludes other campaign branding, data, operating playbooks, and proprietary campaign-specific workflows.
- Deferred modules should only be added if DPG explicitly scopes and approves them.
- Monday should be framed as testing the voter engagement/admin foundation, not as a finished election-day command center.

## Known deferred modules

- DPG membership-vs-GEC automation.
- Household/address canvassing workflow.
- Structured contact attempts by method/outcome.
- Support/lean/donation tracking.
- Precinct/village/district-scoped permissions beyond the current role foundation.
- Poll watcher workflow.
- Real-time voted/not-voted tracking.
- War-room dashboard.
- GIS/maps/heatmaps.
- ID/photo/OCR scanning.
- Autodialer integration.
