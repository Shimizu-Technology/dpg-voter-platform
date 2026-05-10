# DPG Deployment Checklist

## Isolation requirements

- [ ] GitHub repository is DPG-specific and private unless Leon decides otherwise.
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

- [ ] `npm --prefix web run lint`
- [ ] `npm --prefix web run build`
- [ ] `RAILS_ENV=test bundle exec rails zeitwerk:check`
- [ ] `RAILS_ENV=test bundle exec rails db:prepare`
- [ ] Render pre-deploy command uses `DATABASE_URL=$DIRECT_DATABASE_URL bundle exec rails db:migrate:primary` only after `DIRECT_DATABASE_URL` is set.
- [ ] Background worker recurring tasks only reference classes that exist in the DPG build.
- [ ] Source scan has no other-campaign or proprietary workflow terms.
- [ ] Built `web/dist` scan has no other-campaign or proprietary workflow terms.
- [ ] Rails route scan has no deferred election-day/proprietary modules.

## Monday testing scope

- [ ] Public landing page loads with DPG branding.
- [ ] Public signup submits a supporter/contact.
- [ ] Thank-you page renders DPG copy.
- [ ] Admin login works with DPG Clerk app.
- [ ] Supporter/contact list loads.
- [ ] Manual entry works.
- [ ] Import preview/confirm works on a small test CSV.
- [ ] Duplicate review works.
- [ ] Voter-help flags and outreach follow-up work.
- [ ] Users/roles screen works.
- [ ] Districts/precincts screen works.
- [ ] SMS/email settings render safely; do not send live blasts during smoke test unless explicitly approved.

## Handoff notes

- This is the DPG voter engagement platform, built from Shimizu Technology's reusable foundation.
- It excludes other campaign branding, data, operating playbooks, and proprietary campaign-specific workflows.
- Deferred modules should only be added if DPG explicitly scopes and approves them.
