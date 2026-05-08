#!/bin/bash
# Create Plane tickets from Feb 15 meeting feedback
# Run when Plane server (Asus) is available

set -e

API_KEY=$(jq -r .api_key ~/.plane-credentials.json)
BASE="http://100.121.164.36:8080/api/v1/workspaces/shimizu-technology/projects/48591924-6eea-4ace-8629-69c8ce629ea1/issues/"
TODO="f157169e-a0a3-443f-8d18-c030597f99dc"
BACKLOG="2ae1df14-f056-4008-90e3-1f99342b30af"

create_ticket() {
  local name="$1"
  local desc="$2"
  local state="$3"
  local priority="$4"  # 1=urgent, 2=high, 3=medium, 4=low

  echo "Creating: $name"
  curl -s -X POST "$BASE" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"description_html\": \"<p>$desc</p>\",
      \"state\": \"$state\",
      \"priority\": \"$priority\"
    }" | jq -r '.sequence_id // .id'
}

echo "=== Phase 1 (Todo) ==="
create_ticket "Split full name into first name + last name" "Replace single Full Name field with First Name + Last Name on signup and staff entry forms. Add columns, migrate existing data, update all views." "$TODO" "high"
create_ticket "Communication opt-in checkboxes + consent disclaimer" "Add opt-in checkboxes (email/text/both) to signup + staff forms. Add consent disclaimer. Backend fields. Admin filter. SMS blast respects opt-in." "$TODO" "high"
create_ticket "Vetting/verification workflow" "Add verified status (unverified/verified/flagged). All supporters start unverified. Staff marks verified. Dashboard shows verified vs total counts. Bulk verify action. Audit logging." "$TODO" "urgent"
create_ticket "Duplicate detection + flagging" "Check for duplicate phone/email/name+DOB on creation. Don't block - flag for review. Review queue in admin. Staff can resolve (not duplicate or merge)." "$TODO" "high"
create_ticket "Excel/CSV import with review step" "Upload Excel/CSV, preview data, map columns, flag uncertainties, staff approves before commit. Handle Shirley's format." "$TODO" "high"
create_ticket "Excel export + respect filters" "Change CSV to Excel (.xlsx). Export respects active filters/search/sort. Include all columns." "$TODO" "medium"
create_ticket "Customizable welcome SMS text" "Admin setting to edit welcome SMS. Template variables support ({first_name}, etc.)." "$TODO" "medium"
create_ticket "Fix QR code to use production URL" "QR codes point to localhost. Use production URL. Make base URL configurable. Village dropdown." "$TODO" "high"

echo ""
echo "=== Phase 2 (Backlog) ==="
create_ticket "Staff area scoping (village/district filtering)" "Chiefs see only their village. Coordinators see their district. Extend existing RBAC." "$BACKLOG" "medium"
create_ticket "OCR form scanning review flow" "Show parsed data with confidence indicators. Flag uncertain fields. Confirmation step before submit." "$BACKLOG" "medium"
create_ticket "Social media CTA on thank-you page" "Add Instagram + Facebook icons/links to thank-you page. Optionally include in welcome SMS." "$BACKLOG" "low"
create_ticket "Configurable voter quotas from real GEC data" "Get real voter numbers. Make quotas editable per village in admin." "$BACKLOG" "medium"
create_ticket "Village page voter vs supporter number clarification" "Investigate mismatch. Add labels/tooltips to clarify registered voters vs signups." "$BACKLOG" "low"

echo ""
echo "=== Phase 3 (Backlog) ==="
create_ticket "Yard sign + motorcade filter/report" "Filter supporters list by yard_sign and motorcade flags. Exportable report." "$BACKLOG" "low"
create_ticket "Event messaging (SMS/email to RSVPs)" "Send SMS or email to event RSVPs from event detail page." "$BACKLOG" "medium"
create_ticket "Email blast functionality" "Add email blasting alongside SMS. Respect opt_in_email. Use Resend." "$BACKLOG" "medium"
create_ticket "WhatsApp integration" "Research WhatsApp Business API. Needs dedicated phone number + Meta verification." "$BACKLOG" "low"
create_ticket "Weekly/monthly quota periods" "Allow quotas per week or month. Show current period progress." "$BACKLOG" "low"
create_ticket "Absentee ballot handling" "Add absentee flag for military/off-island voters. Link to application form." "$BACKLOG" "low"
create_ticket "Non-registered voter list/outreach" "Filter for unregistered supporters. Outreach queue to help register." "$BACKLOG" "medium"
create_ticket "ActionCable stability improvements" "Fix intermittent disconnects/timeouts. Add reconnection logic with backoff." "$BACKLOG" "medium"
create_ticket "Bulk SMS at scale verification" "Test SMS blast to 100+ recipients. Verify rate limiting. Progress indicator. Delivery receipts." "$BACKLOG" "high"

echo ""
echo "=== Branding/Setup (Backlog) ==="
create_ticket "Domain setup (joshtina.support)" "Purchase domain, configure DNS to Netlify, update CORS/OG tags/sitemap." "$BACKLOG" "medium"
create_ticket "Apply official branding from campaign team" "Get logo from Austin. Apply campaign colors/fonts. Update landing, signup, admin." "$BACKLOG" "medium"
create_ticket "Test events flow end-to-end" "Create event, RSVP, check-in, notifications. Verify full lifecycle." "$BACKLOG" "medium"
create_ticket "Test war room + poll watcher end-to-end" "Full election-day simulation. Poll watcher → war room → strike list → contacts." "$BACKLOG" "medium"

echo ""
echo "=== Done! 26 tickets created ==="
