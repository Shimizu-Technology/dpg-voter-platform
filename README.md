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

The core DPG voter-engagement foundation is now implemented and merged to `main`: public signup, QR/share-link attribution, Contacts/Intake, GEC voter-list import/search/linking, household/address lookup, contact history, Follow-Up Queue, governed SMS/email outreach, reports/export, users/roles, audit logs, and DPG/GEC cross-reference reporting. Public signups, staff entries, and contact imports are visible immediately as DPG contacts and default into Intake for review. A legacy `membership_status` field still exists in the database/model for future official member-roster import or cross-reference work, but membership is intentionally hidden from the manual UI until DPG defines that roster workflow.

## Starter functionality

- Public signup
- Supporter/contact CRM
- GEC voter-list import/search/linking
- Household/address lookup
- Voter-help follow-up
- Manual staff entry
- Spreadsheet contact import
- Duplicate review
- Reports and DPG/GEC cross-reference exports
- Users and roles
- Districts, villages, and precincts
- SMS/email settings and outbound messaging
- Audit logs

## Key next build priorities

1. Run a guided walkthrough with Auntie Stephanie and a small DPG tester group.
2. Confirm production readiness items: Clerk production settings, backups, environment isolation, and controlled SMS/email sender policy.
3. Collect real DPG list samples before building schema-specific importers.
4. Add explicit list types for DPG contacts/supporters, official DPG member rosters, registered Democrat lists, and custom lists once samples exist.
5. Continue refining labels, reports, roles, and workflows with DPG office feedback.

## Boundary

This repository should not carry forward another campaign's private data, branding, proprietary operating playbook, or campaign-specific election-day workflows.
