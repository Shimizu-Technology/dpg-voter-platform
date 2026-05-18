# Democratic Party of Guam Voter Engagement Platform

This repository is a clean DPG-specific application forked from Shimizu Technology campaign operations code.

## Boundary
- DPG has its own deployment, database, auth, secrets, and backups.
- Other campaign data, branding, operating playbooks, and proprietary workflows are intentionally excluded.
- Reusable neutral foundation remains: public signup, contacts/supporters, voter help, imports/exports, reports, users/roles, districts/precincts, settings, and audit logs.

## Deferred unless DPG explicitly scopes it
- Election-day command center
- Poll-site observer operations
- Gamified collection targets
- Campaign-specific event, sign, or parade workflows
- OCR paper-form pipeline

## Current planning docs
- `current-project-status.md` - latest project status, what is implemented, caveats, and deferred work.
- `next-implementation-plan.md` - immediate guided walkthrough checklist and next product phases after PR #37.
- `dpg-product-blueprint.md` - source-of-truth product model and long-term platform plan.
- `monday-testing-handoff.md` - tester walkthrough script; historical filename, now used as the general DPG handoff.
