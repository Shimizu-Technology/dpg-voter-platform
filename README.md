# Campaign Tracker

Campaign supporter tracking, quota management, and election day war room for the Guam gubernatorial election.

## Status: Planning

See [PRD.md](./PRD.md) for full product requirements.

## Documentation Map

- [PRD](./PRD.md) - product requirements and scope
- [System Overview](./docs/system-overview.md) - how the app works end-to-end (architecture, flows, auth, ops)
- [Build Plan](./docs/build-plan.md) - implementation plan and phased roadmap
- [Execution Tracker](./docs/execution-tracker.md) - current work status (Done / Now / Next / Later)
- [RBAC Matrix](./docs/rbac-matrix.md) - role permissions, access boundaries, and QA checklist
- [Testing Handoff Pack](./docs/testing/README.md) - manual QA checklists for engineers (RBAC + critical flows)
- [Issue Audit + Test Plan](./docs/issue-audit-and-test-plan-2026-02-13.md) - validated findings and regression checks

## What This Does

1. **Digital Blue Form** — Replace paper Block List forms with online data entry + QR code self-signup
2. **Quota Tracking** — Real-time dashboards showing supporter collection progress by village/district
3. **Event Check-in** — Motorcade and rally attendance tracking
4. **Election Day War Room** — Poll watcher voter marking, real-time turnout dashboards, auto-generated call bank lists

## Tech Stack

- Rails 8 API + React (TypeScript, Tailwind, Vite)
- PostgreSQL
- Mobile-first design

## Getting Started

### Environment Variables

Set these in your deployment environment (Render/Netlify) and local `.env` files:

- **API (`api/`)**
  - `CLERK_PUBLISHABLE_KEY` - Clerk publishable key used for JWT domain derivation
  - `CLERK_JWT_AUDIENCE` - optional audience check for Clerk JWT verification
  - `AUTO_PROVISION_USERS` - defaults to `false`; set `true` only if you intentionally allow first-login user auto-creation
  - `BOOTSTRAP_ADMIN_EMAILS` - comma-separated user emails to upsert as privileged seed users
  - `BOOTSTRAP_ADMIN_ROLE` - role assigned to bootstrap emails (default: `campaign_admin`)
  - `ALLOWED_ORIGINS` - comma-separated frontend origins for CORS
  - `FRONTEND_URL` - canonical frontend URL for QR/signup links
  - `CLICKSEND_USERNAME`, `CLICKSEND_API_KEY`, `CLICKSEND_SENDER_ID` - SMS provider config
  - `OPENROUTER_API_KEY` - OCR extraction integration
  - `REDIS_URL` - ActionCable production pub/sub backend

- **Web (`web/`)**
  - `VITE_CLERK_PUBLISHABLE_KEY` - Clerk frontend key
  - `VITE_API_URL` - API origin (for production and direct API/cable URL building)

See `api/.env.example` and `web/.env.example` for templates.

Bootstrap flow: run seeds with `BOOTSTRAP_ADMIN_EMAILS` set. On first Clerk login, the API links the Clerk `sub` to the seeded email record and preserves the seeded role.

### Quick Start (Local)

1. Start API: `cd api && bin/rails server -p 3000`
2. Start web: `cd web && npm install && npm run dev`
3. Open app at `http://localhost:5175`

## License

Private — Shimizu Technology LLC
