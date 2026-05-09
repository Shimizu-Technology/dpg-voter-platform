# Monday Scope + Confidence Audit — DPG Voter Platform

## Purpose

Make sure the DPG build is not just a shell. The Monday testing build should include useful core functionality DPG asked for, while keeping Josh/Tina's protected data/workflows/playbook out of the app.

## Monday promise

The first DPG testing build should provide a working foundation for:

- public DPG signup
- supporter/contact CRM
- manual staff entry
- DPG-owned list import
- duplicate review/warnings
- village/precinct organization
- basic users/roles
- basic reports/export
- outreach/follow-up status where already stable
- GEC/public voter-list foundation if stable and generic

It does **not** need to include every advanced item by Monday.

## Explicitly okay to defer

- poll watcher/election-day command center
- war-room dashboard
- voted/not-voted operations
- GIS/heatmaps
- OCR/photo/ID scan
- live SMS/email blasts
- DPG membership-vs-GEC automation if not ready
- household/address grouping if not ready
- DPG-defined district mapping until DPG confirms it

## Boundary rule

Keep reusable Shimizu platform functionality. Remove or disable Josh/Tina-specific implementation details.

- GEC/public voter-list import/search is generally safe and DPG-requested.
- Guam villages and public precincts are generally safe.
- Josh/Tina internal district mapping should not be inherited.
- Blue block-list form and Rose/Trish vetting flow should not be copied into DPG.
- Quota/village-org cadence should stay out unless DPG defines its own goals workflow.

## Audit objective

Review the whole app and produce a concrete confidence checklist:

1. What is already good enough for Monday.
2. What must be cleaned before deployment.
3. What should be added/restored before Monday.
4. What can safely wait.
5. What might break if removed too aggressively.

## Verification gates

Before staging/deployment, run:

- frontend lint
- frontend build
- Rails zeitwerk check
- route scan for deferred modules
- source/dist scan for Josh/Tina/proprietary residue
- smoke test signup → contact record → admin view
- smoke test import → duplicate review/report/export if possible
