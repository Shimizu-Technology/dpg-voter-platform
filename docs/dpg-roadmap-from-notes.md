# DPG Roadmap From Notes And Transcripts

## Purpose

This document translates the Democratic Party of Guam notes/transcripts into a practical delivery roadmap.

The Monday build should be presented as a usable DPG voter-engagement foundation, not the complete election-day operations platform.

## Sources reviewed

- Brain-Dump Democratic Party meeting transcript from April 2, 2026.
- Brain-Dump in-person meeting transcript from April 27, 2026.
- Brain-Dump DPG voter platform notes and implementation plan.
- Repo docs: `current-project-status.md`, `dpg-requested-feature-checklist.md`, `monday-testing-handoff.md`, and `clean-room-implementation-plan.md`.

## Monday-ready foundation

- Public DPG signup and thank-you flow.
- DPG-branded public pages.
- Supporter/contact CRM.
- Manual staff entry.
- CSV/Excel-style supporter import preview and confirm flow.
- Duplicate detection/review.
- Search/filter foundations by village, precinct, status, and related fields.
- Villages and public precinct references.
- Staff users and role/scoped access foundation.
- Basic reports/export.
- Audit logs.
- SMS/email configuration and preview/dry-run surfaces, with live sends disabled unless explicitly approved.

## Requested, but not Monday-ready

- Full GEC voter-list workspace: import/search/review UI for GEC voter files, skipped rows, versioning, and operational workflows.
- DPG membership/supporter cross-reference against GEC voter files.
- Registered Democrat list/member-list support as distinct list types.
- Household/address lookup: search an address and see associated voters/supporters.
- Structured contact history by method: in-person, phone, email, phone bank, canvass, notes, and follow-up history.
- Canvassing/route workflow.
- DPG-branded QR download/share workflow for field signup attribution.
- Live mass SMS/email blasts after opt-in, sender, legal, and provider approval.
- Autodialer export/integration after DPG chooses the provider.
- DPG-owned poll watcher workflow.
- Precinct-scoped poll watcher accounts.
- Election-day voted/not-voted updates.
- Turnout/call-list dashboard.
- War-room reporting.
- GIS/maps/heatmaps.
- ID/photo intake.
- OCR/photo paper-form intake, rebuilt around DPG-defined forms/processes.
- DPG-defined district mapping if DPG wants districts beyond public village/precinct structure.

## Why these are deferred

- The April 27 transcript supports giving DPG "whatever's there now" so the team can get familiar, then adding heavier pieces later.
- Election-day, OCR, quota-like, and poll-watcher modules are high-risk to copy directly from Josh/Tina because they can encode another campaign's operating method.
- DPG did ask for those concepts, but they should be rebuilt or configured from DPG's own process rather than inherited blindly.
- Live outreach has legal, opt-in, sender, deliverability, and provider risks, so Monday should use preview/dry-run unless explicitly approved.

## Recommended next build order

1. Deploy isolated DPG staging/production and smoke-test the Monday foundation.
2. Add the full GEC voter-list workspace and membership/supporter cross-reference.
3. Add household/address lookup and structured contact history.
4. Add QR field signup attribution and downloadable QR assets.
5. Configure live SMS/email only after DPG approves sender, opt-in language, and provider setup.
6. Scope the election-day module with DPG: poll watcher roles, voted/not-voted workflow, turnout dashboard, and war-room reporting.
7. Evaluate maps/heatmaps, autodialer integration, ID/photo intake, and OCR as separate add-ons.

