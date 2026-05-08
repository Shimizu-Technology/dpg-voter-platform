# Campaign Tracker — Build Plan (POC for Feb 15 Meeting)

**Goal:** Walk into Saturday's meeting with a working demo that digitizes the blue form, shows a live dashboard, and tracks event/motorcade attendance.

---

## Decisions Made (Feb 12)

### Scope
- **POC focuses on:** Digital blue form + public QR signup + live dashboard + event attendance tracking
- **Referrals + performance hardening:** Phase 2 (after core functionality works)
- **Districts:** Configurable — admin can create/edit districts and assign villages. Not hardcoded.
- **Election Day War Room:** Phase 4 (future — after primary infrastructure is proven)

### Tech Stack (Following Shimizu Starter-App Playbook)
| Component | Technology | Starter-App Guide |
|-----------|-----------|-------------------|
| **Backend** | Rails 8 API | — |
| **Frontend** | React + TypeScript + Tailwind + Vite | `FRONTEND_DESIGN_GUIDE.md` |
| **Auth** | Clerk (invite-only) | `CLERK_AUTH_SETUP_GUIDE.md` |
| **Database** | PostgreSQL (Neon for prod) | `DEPLOYMENT_GUIDE.md` |
| **Email** | Resend (invites, notifications) | `EMAIL_SETUP_GUIDE.md` |
| **Real-time** | Polling for POC → ActionCable for prod | `WEBSOCKETS_GUIDE.md` |
| **Background Jobs** | GoodJob | `BACKGROUND_JOBS_GUIDE.md` |
| **PWA** | Yes — mobile install for field workers | `PWA_SETUP_GUIDE.md` |
| **Testing** | Browser QA + Playwright | `TESTING_GUIDE.md` |
| **Icons** | lucide-react (SVGs only, no emojis) | `FRONTEND_DESIGN_GUIDE.md` |
| **Animations** | Framer Motion | `FRONTEND_DESIGN_GUIDE.md` |
| **Error Monitoring** | Sentry (post-POC) | `ERROR_MONITORING_GUIDE.md` |
| **Analytics** | PostHog (post-POC) | `ANALYTICS_SETUP_GUIDE.md` |
| **CI/CD** | GitHub Actions (post-POC) | `CI_CD_GUIDE.md` |
| **Hosting** | Render (API) + Netlify (frontend) | `DEPLOYMENT_GUIDE.md` |
| **AI Workflow** | Gate script, closed-loop verification | `AI_DEVELOPMENT_WORKFLOW.md` |
| **Cursor Rules** | Set up for this project | `CURSOR_RULES_SETUP.md` |

### Auth Flow
- **Admin (Leon/Auntie Rose):** Creates accounts for higher-ups
- **Higher-ups:** Can invite lower admins/chiefs/leaders via Clerk invitations
- **No self-registration** for staff — accounts are created by someone above you in the hierarchy
- **Public signup form:** No account needed (QR code / direct link)

### Design Direction
- **Tone:** Professional but accessible — campaign branding (Josh & Tina colors)
- **Mobile-first:** Block leaders and chiefs are in the field on phones
- **PWA installable:** "Add to Home Screen" for native app feel
- **No emojis in UI** — SVG icons only (lucide-react)
- Follow `FRONTEND_DESIGN_GUIDE.md` + `FRONTEND_DESIGN_SKILL.md`

---

## Blue Form Fields (from actual physical form)

**Reference:** `docs/blue-form-reference.jpg`

**Header (auto-filled based on logged-in user):**
- District
- Village
- Section
- Block
- Date (auto)
- Name of Block Leader (auto)
- Contact No. of Block Leader (auto)

**Per Supporter (10 rows on paper):**
| Field | Type | Required? | On Paper Form? |
|-------|------|-----------|----------------|
| Print Name | text | ✅ | ✅ |
| Contact Nos. | phone | ✅ | ✅ |
| DOB | date | ❌ | ✅ |
| Email Address | email | ❌ | ✅ |
| Street Address | text | ❌ | ✅ |
| Registered Voter (Y/N) | boolean | ✅ | ✅ |

**Additional digital fields (not on paper form):**
| Field | Type | Notes |
|-------|------|-------|
| Precinct | select | Auto-detect from village if possible |
| Yard Sign (Y/N) | boolean | "Will you put a sign on your yard?" |
| Motorcade (Y/N) | boolean | "Will you join motorcades?" |
| Source | auto | "staff_entry" / "qr_signup" / "referral" |
| Entered By | auto | User who entered the data |

---

## Data Model

### Campaigns
- name, election_year, election_type (primary/general), status (active/archived)
- candidate_names, party, branding (colors, logo)
- All data below is scoped to a campaign

### Districts (configurable by admin)
- name, number, campaign_id
- coordinator (user reference)

### Villages (reference data, pre-loaded with real GEC data)
- name, district_id, registered_voters, precinct_count
- chief (user reference), co_chief (user reference)
- All 19 Guam villages pre-seeded

### Precincts (reference data, pre-loaded with real GEC data)
- number, alpha_range, village_id, registered_voters, polling_site
- All 72 precincts pre-seeded from Jan 2026 GEC data

### Blocks/Sections
- name, village_id, leader (user reference)

### Users (Clerk-managed auth, app-managed roles)
- clerk_id, name, email, phone, role
- **Roles:** campaign_admin, district_coordinator, village_chief, block_leader, poll_watcher
- assigned_district_id, assigned_village_id, assigned_block_id
- Invitation flow: admin creates → Clerk sends invite email → user activates

### Supporters (the blue form data)
- print_name, contact_number, dob, email, street_address
- village_id, precinct_id, block_id
- registered_voter (boolean)
- yard_sign (boolean), motorcade_available (boolean)
- source: "staff_entry" / "qr_signup" / "referral"
- entered_by_user_id, referred_from_village_id (nullable)
- status: active / inactive / duplicate / unverified
- created_at (auto-timestamp)

### Quotas
- village_id (or district_id), target_count, target_date, period (weekly/monthly/quarterly)

### Events
- name, event_type: "motorcade" / "rally" / "fundraiser" / "meeting" / "other"
- date, time, location, description
- campaign_id, village_id (nullable — some events are island-wide)
- quota (minimum attendees needed)
- status: upcoming / active / completed / cancelled

### Event RSVPs
- event_id, supporter_id
- rsvp_status: "invited" / "confirmed" / "declined" / "no_response"
- attended (boolean — marked day-of via check-in)
- checked_in_at (timestamp, nullable)
- checked_in_by (user reference — who marked them present)

### Supporter Engagement (computed/cached)
Each supporter builds a track record over time:
- events_invited_count
- events_attended_count
- events_no_show_count
- **reliability_score:** (attended / invited) × 100
- last_event_date
- This data helps prioritize who to call on election day:
  - High reliability + hasn't voted = **urgent call**
  - Low reliability + hasn't voted = lower priority
  - Signed up but never attended anything = "paper supporter"

---

## Why Event Tracking Matters

The campaign team needs more than just names — they need to know who **actually shows up**.

**The problem:**
- They set a motorcade quota: "We need 200 cars in Dededo on Saturday"
- 300 people RSVP yes
- Only 150 show up
- Next time, they don't know if they should invite 400 or 500 to hit 200

**What the system solves:**
1. **Quota planning:** "Dededo supporters have a 62% show-up rate, so invite 325 to get 200"
2. **Accountability:** Village chiefs can see which block leaders' supporters are showing up vs. not
3. **Reliability scoring:** Over time, each supporter has a track record (attended 3/5 events = 60% reliable)
4. **Election day prioritization:** When calling supporters who haven't voted, prioritize those who've been showing up to events (they're more likely to follow through)
5. **Leaderboard/gamification:** Which village has the best turnout rate? Which block leader's supporters are most reliable?

**Day-of workflow:**
```
Event created (motorcade) → System pulls RSVPs from supporters
→ Day-of: Staff at check-in searches by name → Taps "Checked In"
→ Dashboard shows: 145/200 arrived (72.5%) — quota not met!
→ Post-event: Report shows who RSVPed yes but didn't show
```

---

## POC Scope (Build for Saturday)

### Must Have
1. **Public signup form** — Mobile-first, campaign-branded, QR code
   - Fields: Name, Phone, Village (dropdown), Street Address, Registered Y/N
   - Optional: Email, Yard Sign, Motorcade
   - "Thank you for supporting Josh & Tina!" confirmation
   - Generates unique QR per block leader (attributed signups)

2. **Staff entry form** — Authenticated, matches blue form layout
   - Auto-fills district/village/block based on logged-in user
   - Bulk mode: submit and immediately start next entry (tab-through)
   - Duplicate detection (same name + village = flag for review)

3. **Live dashboard** — Real-time supporter counts
   - Island-wide view: 19 villages with progress bars toward quota
   - Click village → see precinct-level breakdown + block leaders
   - Supporter count vs quota (thermometer style)
   - New signups today/this week
   - Color coding: Green (on track) / Yellow (behind) / Red (critical)
   - "Names needed per day to hit target" calculation

4. **Event attendance tracking**
   - Create events (motorcade, rally, etc.) with date, location, quota
   - Auto-populate RSVP list from supporters with motorcade_available = true
   - Day-of check-in: search by name → tap "Checked In" → timestamp
   - Post-event dashboard: invited vs attended, percentage, no-shows
   - Supporter reliability score (builds over time)

5. **Seed data** — All 19 villages, 72 precincts, real voter counts from Jan 2026 GEC data

### Nice to Have (if time)
6. Block leader leaderboard (who's collecting the most supporters)
7. CSV export of supporters
8. Basic role-based views (chief sees only their village)
9. Village-level event attendance breakdown
10. PWA manifest (installable on phone)

### Explicitly NOT in POC
- Election day war room (Phase 4)
- Referral system (Phase 2)
- SMS/text capabilities
- Offline mode / service worker
- Campaign finance tracking
- Social media integration

### Phase 2 Additions (Post-POC Hardening)
- **Dashboard performance hardening**
  - Keep query-count optimized dashboard aggregation (bulk grouped counts, no per-village count loops)
  - Add short-lived cache window for `/api/v1/dashboard` (target: 15-30s, with safe busting on supporter/event mutations)
- **War room performance pass**
  - Profile `war_room` endpoint query count and remove N+1 patterns
  - Add focused endpoint performance tests for election-day volume scenarios
- **Database/index tuning**
  - Review and add indexes for frequent filters/sorts (`supporters`, `poll_reports`, `event_rsvps`)
  - Validate with `EXPLAIN` for top read paths used in dashboard/war-room views
- **Observability**
  - Add lightweight request timing + query-count visibility for key admin endpoints in non-production environments
- **Signup/data model enhancements (optional based on operations feedback)**
  - Add supporter confirmation email option (in addition to existing SMS flow)
  - Split `street_address` into structured fields (e.g., street, village, zip/postal code)
  - Make precinct management configurable by admins if districting/commission mappings change
- **Supporter operations and accountability**
  - Add supporter profile page (`/admin/supporters/:id`) with richer details and edit actions
  - Add role-gated supporter edit capabilities (admin/coordinator first)
  - Add audit/history log for supporter changes (who changed what, when)
- **Mobile UX hardening sweep**
  - Complete responsive QA for all admin pages (filters, tables, headers, action bars)
  - Prioritize field-worker screens and supporter management flows for touch-first ergonomics
- **Election-day supporter strike-list operations**
  - Add supporter-level turnout status workflow ("voted" / "not yet voted") for campaign operations
  - Add poll watcher strike-list interface scoped to assigned precincts/villages
  - Add war room view of supporter-level "not yet voted" queues for rapid GOTV outreach
  - Add call outcome logging to track contact attempts and outcomes during election-day push
  - Add legal/compliance notes in-app clarifying campaign-tracked turnout vs official election records

---

## Pages

| Route | Page | Access |
|-------|------|--------|
| `/` | Public landing + signup CTA | Public |
| `/signup` | Public supporter signup form | Public |
| `/signup/:leader_code` | Attributed signup (from block leader QR) | Public |
| `/thank-you` | Confirmation page after signup | Public |
| `/admin` | Dashboard overview (island-wide) | All staff |
| `/admin/supporters` | Supporter list + search + filter + export | All staff |
| `/admin/supporters/:id` | Supporter profile + edit + audit history | All staff (role-gated edits in Phase 2) |
| `/admin/supporters/new` | Staff entry form (digital blue form) | All staff |
| `/admin/villages/:id` | Village detail: supporters, blocks, precincts | Village chief+ |
| `/admin/events` | Event list + create | District coordinator+ |
| `/admin/events/:id` | Event detail: RSVPs, check-in, results | District coordinator+ |
| `/admin/events/:id/checkin` | Day-of check-in interface (mobile-optimized) | All staff |
| `/admin/settings` | District/village/quota/campaign config | Admin only |
| `/admin/users` | User management + invites | Admin only |

---

## User Flows

### Flow 1: Public Supporter Signs Up (QR Code)
```
1. Block leader shows QR code on phone (or printed flyer)
2. Supporter scans QR → opens /signup/:leader_code on their phone
3. Mobile-friendly form: Name, Phone, Village, Address, Registered Y/N
4. Optional: Email, Yard Sign, Motorcade availability
5. Submit → "Si Yu'os Ma'åse! Thank you for supporting Josh & Tina!" page
6. Supporter data appears in dashboard instantly
7. Attributed to the block leader who generated the QR
```

### Flow 2: Block Leader Enters Supporters (Staff Entry)
```
1. Block leader logs in on phone (Clerk auth)
2. Goes to /admin/supporters/new
3. Form pre-fills: District, Village, Section, Block (from their assignment)
4. Enters supporter data (matches blue form fields)
5. Submit → success toast → form clears for next entry (bulk mode)
6. If duplicate detected (same name + village): warning flag, can override
7. Repeat for each supporter on the paper blue form
```

### Flow 3: Village Chief Reviews Progress
```
1. Chief logs in → sees /admin with their village highlighted
2. Dashboard shows: "Tamuning: 347/920 supporters (37.7%)"
3. Clicks into village → sees block-by-block breakdown
4. "John's block: 45 supporters | Maria's block: 32 | Pete's block: 12"
5. Can see which blocks are behind quota
6. Can also enter supporters directly
```

### Flow 4: Admin Creates Motorcade Event
```
1. Admin goes to /admin/events → "New Event"
2. Enters: "Dededo Motorcade", Saturday Feb 22, Dededo, Quota: 200
3. System auto-pulls supporters where motorcade_available = true AND village = Dededo
4. Shows: "312 potential attendees identified"
5. Can send notification (Phase 2) or just share event info
```

### Flow 5: Day-of Motorcade Check-in
```
1. Staff member opens /admin/events/:id/checkin on phone
2. Search bar at top — type supporter name
3. Results appear → tap "Check In" → timestamp recorded
4. Live counter: "147/200 checked in (73.5%)"
5. Can also scan QR if supporter has one (future)
```

### Flow 6: Post-Event Review
```
1. Admin views /admin/events/:id after event
2. Dashboard shows: 312 invited → 189 confirmed → 147 attended
3. Show-up rate: 47.1% of invited, 77.8% of confirmed
4. List of no-shows (confirmed but didn't come)
5. Each supporter's reliability_score updates automatically
6. Admin can see trends: "Dededo has been declining — 82% → 71% → 47%"
```

### Flow 7: Campaign-Wide Dashboard View
```
1. Admin logs in → /admin dashboard
2. Top-level stats: "8,234 / 10,000 supporters (82.3%)"
3. 19 villages each with thermometer bars
4. Color-coded: Green (>75%) / Yellow (50-75%) / Red (<50%)
5. "Danger zones" highlighted — villages falling behind
6. "At current pace, you'll hit 10K by March 15" projection
7. Click any village → drill into precinct/block detail
8. Events section: upcoming motorcades, recent attendance stats
```

---

## Timeline

| Day | What |
|-----|------|
| **Wed night (Feb 12)** | Scaffold Rails + React, data model, migrations, seed all 19 villages + 72 precincts |
| **Thu (Feb 13)** | Public signup form, staff entry form, basic dashboard with progress bars |
| **Fri morning (Feb 14)** | Event tracking: create event, RSVP list, check-in interface |
| **Fri afternoon (Feb 14)** | Polish: QR codes, campaign branding, mobile responsiveness, PWA manifest |
| **Sat (Feb 15)** | Meeting — demo the POC |

---

## Reference Documents
- **Blue form photo:** `docs/blue-form-reference.jpg`
- **Election research:** `docs/guam-election-research.md`
- **Village/precinct data:** `docs/guam-villages.md`
- **Execution tracker (live status):** `docs/execution-tracker.md`
- **Full PRD:** `PRD.md`
- **Shimizu Starter-App guides:** `~/clawd/obsidian-vault/starter-app/`

---

*This build plan is the single source of truth for what we're building and why. Update as decisions are made.*
