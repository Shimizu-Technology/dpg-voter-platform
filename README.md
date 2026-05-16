# Democratic Party of Guam Voter Engagement Platform

DPG-specific voter engagement and party operations application maintained by Shimizu Technology.

The product source of truth is `docs/dpg-product-blueprint.md`.

## Scope

This fork is intentionally built as its own application for the Democratic Party of Guam:

- separate deployment
- separate database
- separate Clerk/auth app
- separate environment variables and secrets
- separate domain/subdomain
- separate backup schedule

## Product direction

This app should become a DPG-owned platform centered on:

- public GEC voter-list import/search
- DPG contacts and intake/classification
- voter-file matching
- household/address lookup
- structured contact history
- outreach follow-up
- role-scoped party operations
- later Election Day operations

The Phase 1 DPG workflow reset is now implemented. Public signups, staff entries, and contact imports are visible immediately as DPG contacts and default into Intake for review. The active staff workflow focuses on whether DPG has contacted the person, what happened, and whether the person supports DPG. A legacy `membership_status` field still exists in the database/model for future official member-roster import or cross-reference work, but membership is intentionally hidden from the manual UI until DPG defines that roster workflow.

## Starter functionality

- Public signup
- Supporter/contact CRM
- Address/email search foundation
- Voter-help follow-up
- Manual staff entry
- Spreadsheet import
- Duplicate review
- Reports
- Users and roles
- Districts, villages, and precincts
- SMS/email settings and outbound messaging
- Audit logs

## Key next build priorities

1. Restore/build the GEC voter-list workspace as public voter-file infrastructure.
2. Add GEC voter search by name, address, village, and precinct.
3. Add structured contact history and household/address canvassing workflows.
4. Add list-type-specific imports for GEC voter list, DPG contacts/supporters, official DPG member rosters, and registered Democrat lists.
5. Continue refining labels, reports, roles, and workflows with DPG office feedback.

## Boundary

This repository should not carry forward another campaign's private data, branding, proprietary operating playbook, or campaign-specific election-day workflows.
