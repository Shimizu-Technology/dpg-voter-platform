# Campaign Tracker — AGENTS.md

## Project Overview
Campaign supporter tracking system for Guam gubernatorial election (Josh Tenorio & Tina Muña Barnes). Replaces paper "Block List" forms with digital data collection, quota tracking, and election day war room.

## Tech Stack
- **Backend:** Rails 8 API-only (Ruby 3.3+)
- **Frontend:** React + Vite + TypeScript + Tailwind CSS v4
- **Database:** PostgreSQL
- **Auth:** Clerk JWT + role-based access (campaign staff only)
- **Hosting:** Render (API) + Netlify (frontend)
- **Real-time:** ActionCable or polling (for election day)

## Architecture
- Monorepo: `api/` + `web/`
- API-first: All data via JSON endpoints
- Mobile-first design (field workers use phones)
- Offline capability needed for election day (Phase 4)

## Key Documents
- `PRD.md` — Full product requirements (START HERE)
- `BUILD_PLAN.md` — Phased build plan with tickets (TBD)
- `.cursor/rules/` — Cursor rules for AI-assisted development

## Design Standards
- Follow `obsidian-vault/jerry/frontend-design-guide.md`
- SVG icons only (no emojis in UI)
- 44px minimum touch targets
- Framer Motion for animations
- Mobile-first responsive design

## Conventions
- Branch naming: `feature/CT-{ticket}-description`
- Commit messages: `CT-{ticket}: Description`
- All PRs to staging first, then main after review

## Critical Dates
- **Feb 23:** First quota deadline (493 names for Tamuning)
- **Aug 1:** Primary Election Day
- **Nov (TBD):** General Election Day
