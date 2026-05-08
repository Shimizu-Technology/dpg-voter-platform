# Campaign Tracker Tickets — Feb 15 Meeting Feedback

**Created:** 2026-02-15
**Source:** Campaign team meeting with Shirley, Austin, Leon
**Plane Project:** CT (48591924-6eea-4ace-8629-69c8ce629ea1)

> Plane server unreachable at time of creation. Run `scripts/create-tickets.sh` when available to sync to Plane.

---

## Phase 1 — This Week (Before Feb 23 Quota Deadline)

### CT-24: Split full name into first name + last name
**Priority:** High | **State:** Todo
- Change signup form: replace single "Full Name" field with "First Name" + "Last Name"
- Update staff entry form the same way
- Backend: add `first_name`, `last_name` columns to supporters table
- Keep `print_name` as computed/display field (last, first)
- Migration to split existing `print_name` data
- Update all list views, detail page, exports
- **Acceptance:** Both forms have separate fields. Existing data migrated. Lists show properly.

### CT-25: Communication opt-in checkboxes + consent disclaimer
**Priority:** High | **State:** Todo
- Add to signup form: "I'd like to receive campaign updates" with separate checkboxes for Email and Text (or both)
- Add consent disclaimer text: "By checking, you agree to receive campaign communications"
- Backend: add `opt_in_email`, `opt_in_text` boolean fields to supporters
- Staff entry form gets same checkboxes
- Admin supporter list: visible column/filter for opt-in status
- SMS blast should only send to people who opted in for text
- **Acceptance:** Checkboxes on both forms. Disclaimer visible. Admin can filter by opt-in. Blast respects opt-in.

### CT-26: Vetting/verification workflow
**Priority:** Critical | **State:** Todo
- Add `verified` status field to supporters (unverified/verified/flagged)
- All new supporters start as `unverified` regardless of source (public or staff entry)
- Staff can mark supporters as `verified` from supporter detail or list
- Dashboard shows two counts: total supporters vs verified supporters
- Quota progress should show verified count (this is what Rose trusts)
- Add bulk verify action for efficiency
- Audit log entry when verification status changes
- **Acceptance:** All supporters have verification status. Dashboard distinguishes counts. Rose's team can vet before counting.

### CT-27: Duplicate detection + flagging
**Priority:** High | **State:** Todo
- On supporter creation (both public + staff), check for potential duplicates by:
  - Same phone number
  - Same email
  - Same first+last name + date of birth
  - Similar name (fuzzy match)
- Do NOT block creation — flag the new entry for review
- Create a "Needs Review" queue/filter in admin (flagged duplicates)
- Staff can mark as "not a duplicate" or merge entries
- **Acceptance:** Duplicates flagged, not blocked. Review queue accessible. Staff can resolve.

### CT-28: Excel/CSV import with review step
**Priority:** High | **State:** Todo (extends CT-22)
- Upload Excel (.xlsx) or CSV file
- Parse and show preview of data before importing
- Map columns (handle: full name → first/last split, missing fields)
- Flag uncertain entries (bad phone format, missing data, potential duplicates)
- Staff reviews and approves before data commits to system
- Handle Shirley's existing format: Name, Contact Number, DOB, Email, Street Address, Registered Y/N
- **Acceptance:** Upload works. Preview shown. Staff approves. Data imports correctly. Uncertainties flagged.

### CT-29: Excel export + respect filters
**Priority:** Medium | **State:** Todo
- Change CSV export to Excel (.xlsx) format
- Export should respect whatever filters/search/sort are currently active
- Include all relevant columns including new fields (verified status, opt-in, etc.)
- **Acceptance:** Downloads .xlsx. Filters applied. All columns present.

### CT-30: Customizable welcome SMS text
**Priority:** Medium | **State:** Todo
- Admin setting to edit the welcome text message sent on signup
- Default: current message
- Support template variables: {first_name}, {last_name}, etc.
- **Acceptance:** Admin can edit message. New signups get customized text.

### CT-31: Fix QR code to use production URL
**Priority:** High | **State:** Todo
- QR code generator currently points to localhost
- Should use production URL (joshtina.support or Netlify URL)
- Make the base URL configurable (env var or admin setting)
- Village dropdown instead of text input for QR generation
- **Acceptance:** QR codes point to live site. Scanning works end-to-end.

---

## Phase 2 — Before Full Team Demo

### CT-32: Staff area scoping (village/district assignment)
**Priority:** Medium | **State:** Backlog
- Chiefs should only see supporters in their assigned village
- Coordinators see their district
- Admin sees everything
- Already partially built (RBAC has assigned_village_id), needs frontend filtering
- **Acceptance:** Staff see only their scope. Admin sees all.

### CT-33: OCR form scanning review flow
**Priority:** Medium | **State:** Backlog
- After OCR scan, show parsed data with confidence indicators
- Flag uncertain/low-confidence fields in yellow
- "Is this correct?" confirmation step before submitting
- Handle name splitting (comma or space detection with asterisk for review)
- **Acceptance:** Scanned data shown for review. Uncertain fields highlighted. Nothing auto-commits.

### CT-34: Social media CTA on thank-you page
**Priority:** Low | **State:** Backlog
- Add Instagram (@joshandtina2026) and Facebook icons/links to thank-you page
- Optionally include in welcome SMS
- **Acceptance:** Social links visible after signup.

### CT-35: Configurable voter quotas from real data
**Priority:** Medium | **State:** Backlog
- Get real voter numbers from mom/Rose
- Make quotas editable per village in admin (already have quota settings page)
- Ensure dashboard reflects real numbers
- **Acceptance:** Real GEC numbers loaded. Quotas editable.

### CT-36: Village page voter vs supporter number explanation
**Priority:** Low | **State:** Backlog
- Investigate why numbers differ (likely: registered voters from GEC vs actual signups)
- Add labels/tooltips to clarify what each number means
- **Acceptance:** Numbers clearly labeled. No confusion.

---

## Phase 3 — Ongoing

### CT-37: Yard sign + motorcade filter/report
**Priority:** Low | **State:** Backlog
- Add filter on supporters list for yard_sign=true, motorcade=true
- Report view showing all yard sign/motorcade volunteers
- **Acceptance:** Filterable. Exportable.

### CT-38: Event messaging (SMS/email to RSVPs)
**Priority:** Medium | **State:** Backlog
- From event detail, send SMS or email to all RSVPs
- Template support
- **Acceptance:** Can message event attendees.

### CT-39: Email blast functionality
**Priority:** Medium | **State:** Backlog
- Add email blasting alongside SMS
- Respect opt_in_email flag
- Use Resend for delivery
- **Acceptance:** Admin can send email blasts. Only to opted-in users.

### CT-40: WhatsApp integration (future)
**Priority:** Low | **State:** Backlog
- Research WhatsApp Business API requirements
- Needs dedicated phone number + Meta verification
- Could replace SMS for better engagement
- **Acceptance:** TBD — needs phone number and Meta approval first.

### CT-41: Weekly/monthly quota periods
**Priority:** Low | **State:** Backlog
- Allow quotas per week or per month, not just overall
- Show progress for current period
- **Acceptance:** Configurable quota periods. Dashboard shows current period progress.

### CT-42: Absentee ballot handling
**Priority:** Low | **State:** Backlog
- Add "absentee" flag/status for military and off-island voters
- Possibly link to absentee ballot application form
- Separate from regular signup flow — just a checkbox or status
- **Acceptance:** Absentee voters identifiable. Link to application if needed.

### CT-43: Non-registered voter list/outreach
**Priority:** Medium | **State:** Backlog
- Filter for supporters where registered_voter=false
- Outreach queue: contact these people to help register
- **Acceptance:** Filter works. Staff can easily find and contact unregistered supporters.

### CT-44: ActionCable stability improvements
**Priority:** Medium | **State:** Backlog
- Investigate intermittent disconnects/timeouts
- Add reconnection logic with backoff
- Consider heartbeat/ping mechanism
- **Acceptance:** No more random disconnects during normal use.

### CT-45: Bulk SMS at scale verification
**Priority:** High | **State:** Backlog
- Test SMS blast to 100+ recipients
- Verify ClickSend handles rate limiting properly
- Add progress indicator for bulk sends
- Verify delivery receipts
- **Acceptance:** Can reliably send to 500+ recipients. Progress shown. Failures surfaced.

---

## Branding & Setup

### CT-46: Domain setup (joshtina.support)
**Priority:** Medium | **State:** Backlog
- Purchase joshtina.support (~$15/yr)
- Configure DNS to point to Netlify
- Update ALLOWED_ORIGINS on Render
- Update canonical URL, OG tags, sitemap
- **Acceptance:** Site accessible at joshtina.support.

### CT-47: Apply official branding (logo, colors from Austin/mom)
**Priority:** Medium | **State:** Backlog
- Get official logo file from Austin
- Colors from joshtina.info: Navy #243872, Red #BC2133, Blue #116DFF
- Replace current J&T icon with official logo
- Update landing page, signup page, admin header
- **Acceptance:** App matches official campaign branding.

### CT-48: Test events flow end-to-end
**Priority:** Medium | **State:** Backlog
- Create event → RSVP → Check-in → Notifications
- Verify full lifecycle works
- **Acceptance:** Complete event flow verified.

### CT-49: Test war room + poll watcher end-to-end
**Priority:** Medium | **State:** Backlog
- Full election-day simulation
- Poll watcher submits → War room updates → Strike list → Contact attempts
- **Acceptance:** Complete election-day flow verified.

---

## Summary

| Phase | Tickets | IDs |
|-------|---------|-----|
| Phase 1 (This Week) | 8 tickets | CT-24 through CT-31 |
| Phase 2 (Before Demo) | 5 tickets | CT-32 through CT-36 |
| Phase 3 (Ongoing) | 9 tickets | CT-37 through CT-45 |
| Branding/Setup | 4 tickets | CT-46 through CT-49 |
| **Total** | **26 tickets** | CT-24 through CT-49 |
