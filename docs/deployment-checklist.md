# DPG Deployment Checklist

## Isolation requirements

- [ ] GitHub repository is DPG-specific and private unless Leon decides otherwise.
- [ ] Backend service uses a DPG-specific `DATABASE_URL`.
- [ ] Frontend service uses a DPG-specific Clerk publishable key.
- [ ] Backend service uses a DPG-specific Clerk secret key.
- [ ] `FRONTEND_URL` points to the DPG frontend domain/subdomain.
- [ ] SMS/email sender settings are DPG-specific or explicitly approved shared infrastructure.
- [ ] Backups are configured for the DPG database before Monday testing.

## Pre-deploy verification

- [ ] `npm --prefix web run lint`
- [ ] `npm --prefix web run build`
- [ ] `RAILS_ENV=test bundle exec rails zeitwerk:check`
- [ ] `RAILS_ENV=test bundle exec rails db:prepare`
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
