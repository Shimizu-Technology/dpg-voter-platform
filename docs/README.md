# Democratic Party of Guam Voter Engagement Platform

This repository is a clean DPG-specific application forked from Shimizu Technology campaign operations code.

## Boundary
- DPG has its own deployment, database, auth, secrets, and backups.
- Other campaign data, branding, operating playbooks, and proprietary workflows are intentionally excluded.
- Reusable neutral foundation remains: public signup, contacts/supporters, voter help, imports/exports, reports, users/roles, districts/precincts, settings, and audit logs.

## Deferred unless DPG explicitly scopes it
- Gamified collection targets beyond DPG-owned quota/period foundation
- Campaign-specific event, sign, or parade workflows
- GIS/maps/heatmaps until DPG confirms use case and data quality
- OCR/photo/ID paper-form pipeline until DPG defines forms and access rules
- Autodialer integration until DPG identifies the tool/process

## Current planning docs
- `dpg-platform-review-and-delivery-plan-2026-07-21.md` - current end-to-end product review, PR #47 findings/completion work, feature matrix, launch gates, and deferred-module rationale.
- `current-project-status.md` - latest project status, what is implemented, caveats, and deferred work.
- `next-implementation-plan.md` - immediate guided walkthrough checklist and next product phases after PR #44.
- `dpg-product-blueprint.md` - source-of-truth product model and long-term platform plan.
- `monday-testing-handoff.md` - tester walkthrough script; historical filename, now used as the general DPG handoff.
- `remaining-work-roadmap.md` - beta QA, production hardening, Election Day validation, list imports, GIS/OCR/autodialer, and other deferred modules.
- `poll-watcher-implementation-plan.md` - detailed review of the adjacent campaign-tracker poll watcher/war-room implementation and the DPG adaptation plan.
- `dpg-open-questions.md` - question list for Auntie Stephanie/Mike Weakley covering Election Day rules, DPG list samples, and cross-reference/reporting decisions.
