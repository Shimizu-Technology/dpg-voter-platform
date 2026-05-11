# DPG Deployment Checklist

**Last updated:** May 11, 2026
**Current verified commit:** `8c8623a Merge pull request #25 from Shimizu-Technology/hotfix/bootstrap-admin-auth`

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
- [ ] `DPG_LIVE_OUTREACH_ENABLED=true` on the intended DPG environment after confirming DPG sender/email/text credentials are present.
- [ ] Dry-run/preview is used for normal smoke testing; real sends are limited to controlled DPG-approved recipients/content.
- [ ] Backups are configured for the DPG database before Monday testing.

## Pre-deploy verification

Verified locally after latest cleanup:

- [x] `cd web && npm run lint -- --max-warnings=0` passed May 11.
- [x] `cd web && npm run build` passed May 11. Local Node is 22.0.0, so Vite emitted a version warning; use Node 22.12+ or 20.19+ for clean local/deploy logs.
- [x] `cd api && eval "$(rbenv init - zsh)" && bundle exec rails test` passed May 11: 173 runs, 636 assertions, 0 failures.
- [x] Ruby environment confirmed with rbenv Ruby 3.3.7 and Bundler 4.0.5.
- [x] Render pre-deploy command uses `DATABASE_URL=$DIRECT_DATABASE_URL bundle exec rails db:migrate:primary` only after `DIRECT_DATABASE_URL` is set.
- [x] Background worker recurring tasks only reference classes that exist in the DPG build.
- [x] Source scan has no active Josh/Tina/quota/war-room/poll-watcher/yard-sign/motorcade routes or Monday-facing UI.
- [x] Built `web/dist` was regenerated May 11 after the production build.
- [x] Rails route scan has no deferred election-day/proprietary modules. Only duplicate-review `scan_duplicates` remains, which is expected.

Local repo note:

- [ ] Resolve untracked root `package-lock.json` before committing/deploy handoff.

## Starter testing scope

Already smoke-tested locally:

- [x] Public signup submits a supporter/contact.
- [x] Thank-you page renders after signup.
- [x] Staff/admin sign-in screens render locally after Clerk loads; authenticated admin workflows are covered by integration/API tests unless a real Clerk login is available.
- [x] Supporter/contact list loads.
- [x] Supporter/contact detail loads.
- [x] Supporter search works by name, phone, email, and street address.
- [x] Manual entry works.
- [x] Staff-entered supporters appear in search/list.
- [x] Import confirm works through authenticated API with a small test CSV.
- [x] Duplicate review API/page loads.
- [x] Reports API and supporter summary preview load.
- [x] Users/roles screen/API loads.
- [x] Audit logs load.
- [x] SMS/email pages render safely.
- [x] SMS/email dry-run works.
- [x] Live SMS/email provider setup is present; dry-run/preview remains available for safe validation.

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
- [ ] Live outreach is enabled only on the intended DPG environment and tested with controlled recipients before any broader blast.

## Handoff notes

- This is the DPG voter engagement platform, built from Shimizu Technology's reusable foundation.
- It excludes other campaign branding, data, operating playbooks, and proprietary campaign-specific workflows.
- The proper next step is the DPG workflow reset in `docs/dpg-product-blueprint.md`.
- GEC voter-list import/search is core public voter-file infrastructure and should be restored/built as a first-class DPG workspace.
- Public signups should be visible contacts, but the final workflow should classify them through Intake before counting them as supporters/members.
- Starter testing should be framed as testing the voter engagement/admin foundation, not as a finished DPG workflow or election-day command center.
- Auntie Stephanie should be created as `campaign_admin` after she provides the email she wants to use.

## Known deferred modules

- Visible DPG Intake queue and classification workflow.
- One internal DPG workspace replacing the Admin/Data Ops split.
- GEC voter-list workspace: import, search, address lookup, and contact matching.
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
