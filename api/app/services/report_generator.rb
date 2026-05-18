# frozen_string_literal: true

# Generates Excel reports for the party data team.
# All reports export to .xlsx format with styled headers.
#
# Report types:
#   - support_list:  Vetted supporters by village
#   - purge_list:    Voters removed from GEC list (deceased/purged)
#   - transfer_list: GEC voters whose village changed between list versions
#   - referral_list: Supporters submitted under the wrong village
#   - mapping_issues_list: GEC voters whose village became unmapped / unassigned
#   - supporter_summary: Totals by village with supporter review status
#   - dpg_contacts_linked_to_gec: DPG contacts already tied to public GEC voters
#   - dpg_contacts_unlinked_from_gec: DPG contacts not tied to public GEC voters
#   - gec_voters_not_in_dpg: Public GEC voters with no linked DPG contact
#   - possible_gec_matches: DPG contacts with a possible/manual GEC match
#   - dpg_gec_mismatches: linked DPG contacts where DPG-entered geography differs from official GEC data
class ReportGenerator
  REPORT_TYPES = %w[
    support_list
    purge_list
    transfer_list
    referral_list
    mapping_issues_list
    supporter_summary
    dpg_contacts_linked_to_gec
    dpg_contacts_unlinked_from_gec
    gec_voters_not_in_dpg
    possible_gec_matches
    dpg_gec_mismatches
  ].freeze

  def initialize(
    report_type:,
    village_id: nil,
    precinct_id: nil,
    district_id: nil,
    campaign_id: nil,
    preview_limit: 100,
    registered_voter_status: nil,
    support_status: nil,
    membership_status: nil,
    volunteer_status: nil,
    support_need: nil,
    registration_outreach_status: nil,
    support_follow_up_status: nil,
    outreach_status: nil
  )
    @report_type = report_type
    @village_id = village_id
    @precinct_id = precinct_id
    @district_id = district_id
    @campaign_id = campaign_id
    @preview_limit = preview_limit
    @registered_voter_status = registered_voter_status
    @support_status = support_status
    @membership_status = membership_status
    @volunteer_status = volunteer_status
    @support_need = support_need
    @registration_outreach_status = registration_outreach_status.presence || outreach_status
    @support_follow_up_status = support_follow_up_status
  end

  def generate
    raise ArgumentError, "Unknown report type: #{@report_type}" unless REPORT_TYPES.include?(@report_type)

    send("generate_#{@report_type}")
  end

  def preview
    raise ArgumentError, "Unknown report type: #{@report_type}" unless REPORT_TYPES.include?(@report_type)

    send("preview_#{@report_type}")
  end

  private

  def header_style(workbook)
    workbook.styles.add_style(
      b: true,
      bg_color: "1B3A6B",
      fg_color: "FFFFFF",
      alignment: { horizontal: :center },
      border: { style: :thin, color: "000000" }
    )
  end

  def date_today
    Date.current.strftime("%m-%d-%Y")
  end

  def format_date(value)
    return nil if value.blank?

    value.strftime("%m/%d/%Y")
  end

  def apply_supporter_geography_filters(scope)
    scope = scope.where(village_id: @village_id) if @village_id.present?
    scope = scope.where(precinct_id: @precinct_id) if @precinct_id.present?
    scope = scope.joins(:village).where(villages: { district_id: @district_id }) if @district_id.present?
    scope
  end

  def apply_gec_geography_filters(scope)
    scope = scope.where(village_id: @village_id) if @village_id.present?
    scope = scope.where(precinct_id: @precinct_id) if @precinct_id.present?
    scope = scope.joins(:village).where(villages: { district_id: @district_id }) if @district_id.present?
    scope
  end

  def filtered_villages
    scope = Village.includes(:precincts).order(:name)
    scope = scope.where(id: @village_id) if @village_id.present?
    scope = scope.where(district_id: @district_id) if @district_id.present?
    scope
  end

  def apply_supporter_report_filters(scope)
    scope = scope.where(registered_voter_status: @registered_voter_status) if @registered_voter_status.present?
    scope = scope.where(support_status: @support_status) if @support_status.present?
    scope = scope.where(membership_status: @membership_status) if @membership_status.present?
    scope = scope.where(volunteer_status: @volunteer_status) if @volunteer_status.present?
    scope = scope.where(registration_outreach_status: @registration_outreach_status) if @registration_outreach_status.present?
    scope = scope.where(support_follow_up_status: @support_follow_up_status) if @support_follow_up_status.present?
    apply_support_need_filter(scope)
  end

  def apply_support_need_filter(scope)
    case @support_need
    when "registration"
      scope.where(needs_voter_registration_help: true)
    when "absentee"
      scope.where(needs_absentee_ballot_help: true)
    when "homebound"
      scope.where(needs_homebound_voting_help: true)
    when "ride"
      scope.where(needs_election_day_ride: true)
    when "volunteer"
      scope.where(wants_to_volunteer: true)
    when "any"
      scope.needs_campaign_help
    else
      scope
    end
  end

  def support_request_summary(supporter)
    requests = []
    requests << "Registration" if supporter.needs_voter_registration_help
    requests << "Absentee" if supporter.needs_absentee_ballot_help
    requests << "Homebound" if supporter.needs_homebound_voting_help
    requests << "Ride" if supporter.needs_election_day_ride
    requests << "Volunteer" if supporter.wants_to_volunteer
    requests.join(", ").presence
  end

  def registration_follow_up_result_label(status)
    case status
    when "registered"
      "Registered via follow-up"
    when "contacted"
      "Contacted"
    when "declined"
      "Declined"
    else
      nil
    end
  end

  def support_follow_up_result_label(status)
    case status
    when "in_progress"
      "In progress"
    when "completed"
      "Completed"
    when "declined"
      "Declined"
    else
      nil
    end
  end

  def supporter_report_headers(base_headers)
    base_headers + [
      "Self-Reported Voter Status",
      "Votes Elsewhere Note",
      "Campaign Requests",
      "Registration Follow-Up Result",
      "Support Follow-Up Result",
      "Referred By",
      "Household Signup"
    ]
  end

  def supporter_report_values(supporter)
    [
      supporter.registered_voter_status&.humanize,
      supporter.registered_voter_location_note,
      support_request_summary(supporter),
      registration_follow_up_result_label(supporter.registration_outreach_status),
      support_follow_up_result_label(supporter.support_follow_up_status),
      supporter.referred_by_name,
      supporter.household_group_id.present? ? "Yes" : nil
    ]
  end

  def support_list_scope
    scope = Supporter.official_supporters.includes(:village, :precinct, :entered_by, :gec_voter)
    scope = apply_supporter_geography_filters(scope)
    apply_supporter_report_filters(scope)
  end

  def transfer_scope
    scope = GecVoter.transferred
      .where.not(village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
      .where.not(previous_village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
      .includes(:village)
    apply_gec_geography_filters(scope)
  end

  def referral_scope
    scope = Supporter.official_supporters.submitted_village_referrals.includes(:village, :submitted_village, :entered_by, :precinct)
    scope = scope.where(submitted_village_id: @village_id) if @village_id.present?
    scope = scope.joins(:village).where(villages: { district_id: @district_id }) if @district_id.present?
    scope = scope.where(precinct_id: @precinct_id) if @precinct_id.present?
    apply_supporter_report_filters(scope)
  end

  def mapping_issue_scope
    scope = GecVoter.transferred
      .where(village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
      .or(
        GecVoter.transferred.where(previous_village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
      )
      .includes(:village)
    apply_gec_geography_filters(scope)
  end

  def purge_scope
    scope = GecVoter.where(status: "removed")
    apply_gec_geography_filters(scope)
  end

  def dpg_contact_scope
    scope = Supporter.contacts.includes(:village, :precinct, :gec_voter, :entered_by)
    scope = apply_supporter_geography_filters(scope)
    apply_supporter_report_filters(scope)
  end

  def dpg_contacts_linked_to_gec_scope
    dpg_contact_scope.where.not(gec_voter_id: nil)
  end

  def dpg_contacts_unlinked_from_gec_scope
    dpg_contact_scope.where(gec_voter_id: nil)
  end

  def possible_gec_matches_scope
    dpg_contacts_unlinked_from_gec_scope.where(verification_status: "flagged")
  end

  def gec_voters_not_in_dpg_scope
    linked_voter_ids = Supporter.contacts.where.not(gec_voter_id: nil).select(:gec_voter_id)
    scope = GecVoter.active.where.not(id: linked_voter_ids).includes(:village, :precinct)
    apply_gec_geography_filters(scope)
  end

  # Build a lookup hash of GEC voters keyed by [lowercase_first, lowercase_last, dob]
  # to avoid N+1 queries in support list generation.
  def build_gec_lookup(supporters)
    return {} if supporters.empty?

    # Filter GEC query to only matching DOBs (avoids loading entire voter table)
    dobs = supporters.filter_map(&:dob).uniq
    return {} if dobs.empty?

    lookup = {}
    GecVoter.active.where(dob: dobs).find_each do |gv|
      key = [ gv.first_name.downcase.strip, gv.last_name.downcase.strip, gv.dob ]
      lookup[key] ||= gv
    end
    lookup
  end

  def lookup_gec_voter(gec_lookup, supporter)
    return nil unless supporter.first_name.present? && supporter.last_name.present? && supporter.dob.present?
    gec_lookup[[ supporter.first_name.downcase.strip, supporter.last_name.downcase.strip, supporter.dob ]]
  end

  def gec_voter_for_report(gec_lookup, supporter)
    supporter.gec_voter || lookup_gec_voter(gec_lookup, supporter)
  end

  # ── Support List ──────────────────────────────────────────────
  # All approved official supporters, grouped by village
  def generate_support_list
    scope = support_list_scope
    scope = scope.order("villages.name", :last_name, :first_name)

    all_supporters = scope.to_a
    gec_lookup = build_gec_lookup(all_supporters)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = supporter_report_headers([
      "Last Name", "First Name", "DOB", "Phone", "Street Address",
      "DPG Village", "DPG Precinct", "GEC Voter Reg #", "GEC Village", "GEC Precinct", "GEC Address", "Date Submitted",
      "Submitted By", "Verification Status"
    ])

    if @village_id.present?
      village = Village.find_by(id: @village_id) || raise(ArgumentError, "Village not found")
      add_support_sheet(wb, village.name, headers, all_supporters, gec_lookup)
    else
      grouped = all_supporters.group_by { |s| s.village&.name || "Unknown" }
      grouped.sort_by { |name, _| name }.each do |village_name, supporters|
        add_support_sheet(wb, village_name, headers, supporters, gec_lookup)
      end
    end

    { package: package, filename: "support-list-#{date_today}.xlsx" }
  end

  def add_support_sheet(workbook, sheet_name, headers, supporters, gec_lookup)
    safe_name = sheet_name.to_s[0..30]
    workbook.add_worksheet(name: safe_name) do |sheet|
      sheet.add_row headers, style: header_style(workbook)
      supporters.each do |s|
        gec_match = gec_voter_for_report(gec_lookup, s)
        sheet.add_row [
          s.last_name, s.first_name, s.dob&.strftime("%m/%d/%Y"),
          s.contact_number, s.street_address,
          s.village&.name, s.precinct&.number,
          gec_match&.voter_registration_number,
          gec_match&.village_name,
          gec_match&.precinct_number,
          gec_match&.address,
          s.created_at&.strftime("%m/%d/%Y"),
          s.entered_by&.name || "System",
          s.verification_status&.humanize,
          *supporter_report_values(s)
        ]
      end
      sheet.column_widths(*Array.new(headers.length, 18))
    end
  end

  # ── Purge List ────────────────────────────────────────────────
  # GEC voters who were on the previous list but not on the current one
  def generate_purge_list
    current_date = GecVoter.maximum(:gec_list_date)
    return empty_report("purge-list", "No GEC data available") unless current_date

    purged = purge_scope
    purged = purged.order(:village_name, :last_name, :first_name)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = [ "Last Name", "First Name", "DOB", "Village", "Voter Reg #",
                "Reason", "Last GEC List Date" ]

    wb.add_worksheet(name: "Purge List") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      purged.each do |gv|
        sheet.add_row [
          gv.last_name, gv.first_name, gv.dob&.strftime("%m/%d/%Y"),
          gv.village_name, gv.voter_registration_number,
          "Removed from GEC list",
          gv.gec_list_date&.strftime("%m/%d/%Y")
        ]
      end
      sheet.column_widths 15, 15, 12, 15, 15, 25, 15
    end

    { package: package, filename: "purge-list-#{date_today}.xlsx" }
  end

  # ── Transfer List ─────────────────────────────────────────────
  # GEC voters whose registration village changed between list versions
  def generate_transfer_list
    scope = transfer_scope
    scope = scope.order(:last_name, :first_name)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = [ "Last Name", "First Name", "DOB", "Voter Reg #",
                "Previous Village", "Current Village",
                "Latest GEC List Date", "Explanation" ]

    wb.add_worksheet(name: "Transfer List") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      scope.each do |gv|
        sheet.add_row [
          gv.last_name, gv.first_name, gv.dob&.strftime("%m/%d/%Y"),
          gv.voter_registration_number,
          gv.previous_village_name,
          gv.village_name,
          gv.gec_list_date&.strftime("%m/%d/%Y"),
          "Moved from #{gv.previous_village_name} to #{gv.village_name} on the latest GEC list"
        ]
      end
      sheet.column_widths 15, 15, 12, 15, 18, 18, 15, 45
    end

    { package: package, filename: "transfer-list-#{date_today}.xlsx" }
  end

  # ── Referral List ─────────────────────────────────────────────
  # Official supporters whose original submitted village differs from current assigned village
  def generate_referral_list
    scope = referral_scope
    scope = scope.order(:last_name, :first_name)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = supporter_report_headers([
      "Last Name", "First Name", "DOB", "Phone",
      "Submitted Under", "Current Assigned Village",
      "Submitted By", "Date", "Referral Reason"
    ])

    wb.add_worksheet(name: "Referral List") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      scope.each do |s|
        sheet.add_row [
          s.last_name, s.first_name, s.dob&.strftime("%m/%d/%Y"),
          s.contact_number,
          s.submitted_village&.name,
          s.village&.name || "Unknown",
          s.entered_by&.name || "System",
          s.created_at&.strftime("%m/%d/%Y"),
          "Submitted under #{s.submitted_village&.name || 'Unknown'} but currently assigned to #{s.village&.name || 'Unknown'}",
          *supporter_report_values(s)
        ]
      end
      sheet.column_widths 15, 15, 12, 15, 18, 18, 15, 12, 45, 18, 24, 24, 24, 18, 16
    end

    { package: package, filename: "referral-list-#{date_today}.xlsx" }
  end

  # ── Mapping Issues List ───────────────────────────────────────
  # GEC voters whose village became unassigned / unmapped between list versions
  def generate_mapping_issues_list
    scope = mapping_issue_scope.order(:last_name, :first_name)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = [ "Last Name", "First Name", "DOB", "Voter Reg #",
                "Previous Village", "Current Mapping",
                "Latest GEC List Date", "Issue" ]

    wb.add_worksheet(name: "Village Mapping Issues") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      scope.each do |gv|
        sheet.add_row [
          gv.last_name, gv.first_name, gv.dob&.strftime("%m/%d/%Y"),
          gv.voter_registration_number,
          gv.previous_village_name,
          gv.village_name,
          gv.gec_list_date&.strftime("%m/%d/%Y"),
          "Latest GEC village could not be mapped cleanly to an official village"
        ]
      end
      sheet.column_widths 15, 15, 12, 15, 18, 18, 15, 45
    end

    { package: package, filename: "village-mapping-issues-#{date_today}.xlsx" }
  end

  # ── Supporter Summary ─────────────────────────────────────────────
  # Per-village totals for the current period: target, approved count, progress
  def generate_supporter_summary
    villages = filtered_villages
    village_ids = villages.map(&:id)

    matched_counts = Supporter.working_supporters.verified.where(village_id: village_ids).group(:village_id).count
    total_counts = Supporter.working_supporters.where(village_id: village_ids).group(:village_id).count
    public_counts = Supporter.active.public_signups.where(village_id: village_ids).group(:village_id).count
    unreg_counts = Supporter.working_supporters.where(village_id: village_ids, registered_voter: false).group(:village_id).count
    team_counts = Supporter.team_input.where(village_id: village_ids).group(:village_id).count

    package = Axlsx::Package.new
    wb = package.workbook
    headers = [ "Village", "Official Supporters", "Matched To GEC", "Team Submitted",
                "Public Signups", "Unregistered", "Review Status" ]

    wb.add_worksheet(name: "Supporter Summary") do |sheet|
      sheet.add_row headers, style: header_style(wb)

      grand_total = 0
      grand_matched = 0
      grand_team = 0
      grand_public = 0
      grand_unregistered = 0

      villages.each do |v|
        total = total_counts[v.id] || 0
        matched = matched_counts[v.id] || 0
        team = team_counts[v.id] || 0
        public_count = public_counts[v.id] || 0
        unregistered = unreg_counts[v.id] || 0
        status = public_count.positive? ? "Needs Review" : "Current"

        grand_total += total
        grand_matched += matched
        grand_team += team
        grand_public += public_count
        grand_unregistered += unregistered

        sheet.add_row [ v.name, total, matched, team, public_count, unregistered, status ]
      end

      total_style = wb.styles.add_style(b: true, border: { style: :thin, color: "000000" })
      sheet.add_row [ "TOTAL", grand_total, grand_matched, grand_team, grand_public, grand_unregistered, "" ],
                    style: total_style

      sheet.column_widths 18, 18, 16, 16, 16, 14, 14
    end

    { package: package, filename: "supporter-summary-#{date_today}.xlsx" }
  end

  # ── DPG / GEC Cross-Reference Reports ─────────────────────────

  def generate_dpg_contacts_linked_to_gec
    generate_supporter_cross_reference_report(
      scope: dpg_contacts_linked_to_gec_scope.order(:last_name, :first_name),
      sheet_name: "Linked DPG Contacts",
      filename: "dpg-contacts-linked-to-gec-#{date_today}.xlsx",
      include_gec_columns: true,
      status_label: "Linked to GEC"
    )
  end

  def generate_dpg_contacts_unlinked_from_gec
    generate_supporter_cross_reference_report(
      scope: dpg_contacts_unlinked_from_gec_scope.order(:last_name, :first_name),
      sheet_name: "Unlinked DPG Contacts",
      filename: "dpg-contacts-unlinked-from-gec-#{date_today}.xlsx",
      include_gec_columns: false,
      status_label: "No linked GEC voter"
    )
  end

  def generate_possible_gec_matches
    generate_supporter_cross_reference_report(
      scope: possible_gec_matches_scope.order(:last_name, :first_name),
      sheet_name: "Possible GEC Matches",
      filename: "possible-gec-matches-#{date_today}.xlsx",
      include_gec_columns: false,
      status_label: "Needs manual GEC review",
      include_match_note: true
    )
  end

  def generate_gec_voters_not_in_dpg
    scope = gec_voters_not_in_dpg_scope.order(:village_name, :last_name, :first_name)

    package = Axlsx::Package.new
    wb = package.workbook
    headers = [ "GEC Voter ID", "Last Name", "First Name", "DOB", "Birth Year", "Address", "Village", "Precinct", "Voter Reg #", "GEC List Date", "Status" ]

    wb.add_worksheet(name: "GEC Not In DPG") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      scope.each do |voter|
        sheet.add_row gec_voter_cross_reference_values(voter)
      end
      sheet.column_widths 12, 16, 16, 12, 10, 30, 18, 10, 16, 14, 20
    end

    { package: package, filename: "gec-voters-not-in-dpg-#{date_today}.xlsx" }
  end

  def generate_dpg_gec_mismatches
    package = Axlsx::Package.new
    wb = package.workbook
    headers = dpg_gec_mismatch_headers

    wb.add_worksheet(name: "DPG GEC Mismatches") do |sheet|
      sheet.add_row headers, style: header_style(wb)
      each_ordered_dpg_gec_mismatch_batch do |candidates|
        supporters = candidates.select { |supporter| dpg_gec_mismatch_types(supporter).any? }
        latest_contact_attempts = LatestSupporterContactAttempts.call(supporters)
        supporters.each do |supporter|
          sheet.add_row dpg_gec_mismatch_values(supporter, latest_contact_attempt: latest_contact_attempts[supporter.id])
        end
      end
      sheet.column_widths(*Array.new(headers.length, 18))
    end

    { package: package, filename: "dpg-gec-mismatches-#{date_today}.xlsx" }
  end

  # ── Preview Helpers ───────────────────────────────────────────

  def preview_support_list
    scope = support_list_scope.left_joins(:village).order("villages.name ASC", "supporters.last_name ASC", "supporters.first_name ASC")
    total_count = scope.count
    rows = scope.limit(@preview_limit).to_a
    gec_lookup = build_gec_lookup(rows)

    {
      columns: supporter_report_headers([
        "Last Name", "First Name", "DOB", "Phone", "Street Address",
        "DPG Village", "DPG Precinct", "GEC Voter Reg #", "GEC Village", "GEC Precinct", "GEC Address",
        "Date Submitted", "Submitted By", "Verification Status"
      ]),
      rows: rows.map do |s|
        gec_match = gec_voter_for_report(gec_lookup, s)
        [
          s.last_name, s.first_name, format_date(s.dob), s.contact_number, s.street_address,
          s.village&.name, s.precinct&.number, gec_match&.voter_registration_number,
          gec_match&.village_name, gec_match&.precinct_number, gec_match&.address,
          format_date(s.created_at), s.entered_by&.name || "System", s.verification_status&.humanize,
          *supporter_report_values(s)
        ]
      end,
      total_count: total_count
    }
  end

  def preview_purge_list
    scope = purge_scope.order(:village_name, :last_name, :first_name)
    total_count = scope.count
    rows = scope.limit(@preview_limit)

    {
      columns: [ "Last Name", "First Name", "DOB", "Village", "Voter Reg #", "Reason", "Last GEC List Date" ],
      rows: rows.map do |gv|
        [
          gv.last_name, gv.first_name, format_date(gv.dob), gv.village_name,
          gv.voter_registration_number, "Removed from GEC list", format_date(gv.gec_list_date)
        ]
      end,
      total_count: total_count
    }
  end

  def preview_transfer_list
    scope = transfer_scope.order(:last_name, :first_name)
    total_count = scope.count
    rows = scope.limit(@preview_limit)

    {
      columns: [ "Last Name", "First Name", "DOB", "Voter Reg #", "Previous Village", "Current Village", "Latest GEC List Date", "Explanation" ],
      rows: rows.map do |gv|
        [
          gv.last_name, gv.first_name, format_date(gv.dob), gv.voter_registration_number,
          gv.previous_village_name, gv.village_name, format_date(gv.gec_list_date),
          "Moved from #{gv.previous_village_name} to #{gv.village_name} on the latest GEC list"
        ]
      end,
      total_count: total_count
    }
  end

  def preview_referral_list
    scope = referral_scope.order(:last_name, :first_name)
    total_count = scope.count
    rows = scope.limit(@preview_limit)

    {
      columns: supporter_report_headers([
        "Last Name", "First Name", "DOB", "Phone", "Submitted Under", "Current Assigned Village", "Submitted By", "Date", "Referral Reason"
      ]),
      rows: rows.map do |s|
        [
          s.last_name, s.first_name, format_date(s.dob), s.contact_number,
          s.submitted_village&.name, s.village&.name || "Unknown", s.entered_by&.name || "System", format_date(s.created_at),
          "Submitted under #{s.submitted_village&.name || 'Unknown'} but currently assigned to #{s.village&.name || 'Unknown'}",
          *supporter_report_values(s)
        ]
      end,
      total_count: total_count
    }
  end

  def preview_mapping_issues_list
    scope = mapping_issue_scope.order(:last_name, :first_name)
    total_count = scope.count
    rows = scope.limit(@preview_limit)

    {
      columns: [ "Last Name", "First Name", "DOB", "Voter Reg #", "Previous Village", "Current Mapping", "Latest GEC List Date", "Issue" ],
      rows: rows.map do |gv|
        [
          gv.last_name, gv.first_name, format_date(gv.dob), gv.voter_registration_number,
          gv.previous_village_name, gv.village_name, format_date(gv.gec_list_date),
          "Latest GEC village could not be mapped cleanly to an official village"
        ]
      end,
      total_count: total_count
    }
  end

  def preview_supporter_summary
    villages = filtered_villages
    village_ids = villages.map(&:id)

    matched_counts = Supporter.working_supporters.verified.where(village_id: village_ids).group(:village_id).count
    total_counts = Supporter.working_supporters.where(village_id: village_ids).group(:village_id).count
    public_counts = Supporter.active.public_signups.where(village_id: village_ids).group(:village_id).count
    unreg_counts = Supporter.working_supporters.where(village_id: village_ids, registered_voter: false).group(:village_id).count
    team_counts = Supporter.team_input.where(village_id: village_ids).group(:village_id).count

    rows = villages.limit(@preview_limit).map do |v|
      total = total_counts[v.id] || 0
      public_count = public_counts[v.id] || 0
      [
        v.name,
        total,
        matched_counts[v.id] || 0,
        team_counts[v.id] || 0,
        public_count,
        unreg_counts[v.id] || 0,
        public_count.positive? ? "Needs Review" : "Current"
      ]
    end

    {
      columns: [ "Village", "Official Supporters", "Matched To GEC", "Team Submitted", "Public Signups", "Unregistered", "Review Status" ],
      rows: rows,
      total_count: villages.count
    }
  end

  def preview_dpg_contacts_linked_to_gec
    preview_supporter_cross_reference(
      scope: dpg_contacts_linked_to_gec_scope.order(:last_name, :first_name),
      include_gec_columns: true,
      status_label: "Linked to GEC"
    )
  end

  def preview_dpg_contacts_unlinked_from_gec
    preview_supporter_cross_reference(
      scope: dpg_contacts_unlinked_from_gec_scope.order(:last_name, :first_name),
      include_gec_columns: false,
      status_label: "No linked GEC voter"
    )
  end

  def preview_possible_gec_matches
    preview_supporter_cross_reference(
      scope: possible_gec_matches_scope.order(:last_name, :first_name),
      include_gec_columns: false,
      status_label: "Needs manual GEC review",
      include_match_note: true
    )
  end

  def preview_gec_voters_not_in_dpg
    scope = gec_voters_not_in_dpg_scope.order(:village_name, :last_name, :first_name)
    total_count = scope.count

    {
      columns: [ "GEC Voter ID", "Last Name", "First Name", "DOB", "Birth Year", "Address", "Village", "Precinct", "Voter Reg #", "GEC List Date", "Status" ],
      rows: scope.limit(@preview_limit).map { |voter| gec_voter_cross_reference_values(voter) },
      total_count: total_count
    }
  end

  def preview_dpg_gec_mismatches
    supporters = []
    each_ordered_dpg_gec_mismatch_batch do |candidates|
      candidates.each do |supporter|
        next if dpg_gec_mismatch_types(supporter).empty?

        supporters << supporter
        break if supporters.length >= @preview_limit
      end
      break if supporters.length >= @preview_limit
    end
    latest_contact_attempts = LatestSupporterContactAttempts.call(supporters)

    {
      columns: dpg_gec_mismatch_headers,
      rows: supporters.map do |supporter|
        dpg_gec_mismatch_values(supporter, latest_contact_attempt: latest_contact_attempts[supporter.id])
      end
    }
  end

  # ── Helpers ───────────────────────────────────────────────────

  def generate_supporter_cross_reference_report(scope:, sheet_name:, filename:, include_gec_columns:, status_label:, include_match_note: false)
    package = Axlsx::Package.new
    wb = package.workbook
    headers = supporter_cross_reference_headers(include_gec_columns: include_gec_columns, include_match_note: include_match_note)
    supporters = scope.to_a
    latest_contact_attempts = LatestSupporterContactAttempts.call(supporters)

    wb.add_worksheet(name: sheet_name.to_s[0..30]) do |sheet|
      sheet.add_row headers, style: header_style(wb)
      supporters.each do |supporter|
        sheet.add_row supporter_cross_reference_values(
          supporter,
          include_gec_columns: include_gec_columns,
          status_label: status_label,
          include_match_note: include_match_note,
          latest_contact_attempt: latest_contact_attempts[supporter.id]
        )
      end
      sheet.column_widths(*Array.new(headers.length, 18))
    end

    { package: package, filename: filename }
  end

  def preview_supporter_cross_reference(scope:, include_gec_columns:, status_label:, include_match_note: false)
    total_count = scope.count
    supporters = scope.limit(@preview_limit).to_a
    latest_contact_attempts = LatestSupporterContactAttempts.call(supporters)
    {
      columns: supporter_cross_reference_headers(include_gec_columns: include_gec_columns, include_match_note: include_match_note),
      rows: supporters.map do |supporter|
        supporter_cross_reference_values(
          supporter,
          include_gec_columns: include_gec_columns,
          status_label: status_label,
          include_match_note: include_match_note,
          latest_contact_attempt: latest_contact_attempts[supporter.id]
        )
      end,
      total_count: total_count
    }
  end

  def supporter_cross_reference_headers(include_gec_columns:, include_match_note:)
    headers = [
      "Contact ID",
      "Last Name",
      "First Name",
      "DOB",
      "Phone",
      "Email",
      "Street Address",
      "Village",
      "Precinct",
      "Classification",
      "Support Status",
      "Volunteer Status",
      "Self-Reported Voter Status",
      "Campaign Requests",
      "Origin",
      "QR/Source Code",
      "Created Date",
      "Verification",
      "Cross-Reference Status",
      "Suggested Action",
      "Last Contact Method",
      "Last Contact Outcome",
      "Last Contact Date",
      "Last Contact Note"
    ]
    headers += [ "GEC Voter ID", "GEC Reg #", "GEC Village", "GEC Precinct", "GEC Address", "GEC Birth Year" ] if include_gec_columns
    headers << "Match Review Note" if include_match_note
    headers
  end

  def supporter_cross_reference_values(supporter, include_gec_columns:, status_label:, include_match_note:, latest_contact_attempt: nil)
    values = [
      supporter.id,
      supporter.last_name,
      supporter.first_name,
      format_date(supporter.dob),
      supporter.contact_number,
      supporter.email,
      supporter.street_address,
      supporter.village&.name,
      supporter.precinct&.number,
      supporter.contact_classification&.humanize,
      supporter.support_status&.humanize,
      supporter.volunteer_status&.humanize,
      supporter.registered_voter_status&.humanize,
      support_request_summary(supporter),
      source_label(supporter),
      supporter.leader_code,
      format_date(supporter.created_at),
      supporter.verification_status&.humanize,
      status_label,
      cross_reference_suggested_action(supporter, status_label: status_label, include_match_note: include_match_note),
      latest_contact_attempt&.channel&.humanize,
      latest_contact_attempt&.outcome&.humanize,
      format_date(latest_contact_attempt&.recorded_at),
      latest_contact_attempt&.note
    ]

    if include_gec_columns
      voter = supporter.gec_voter
      values += [
        voter&.id,
        voter&.voter_registration_number,
        voter&.village_name,
        voter&.precinct_number,
        voter&.address,
        voter&.birth_year
      ]
    end

    values << possible_match_note(supporter) if include_match_note
    values
  end

  def possible_match_note(supporter)
    metadata = supporter.verification_reason_metadata || {}
    [
      supporter.verification_reason&.humanize,
      metadata["confidence"].presence && "Confidence: #{metadata['confidence']}",
      metadata["match_type"].presence && "Match: #{metadata['match_type'].to_s.humanize}",
      metadata["match_count"].presence && "Candidates: #{metadata['match_count']}",
      metadata["gec_village_name"].presence && "GEC village: #{metadata['gec_village_name']}"
    ].compact.join(" · ")
  end

  def dpg_gec_mismatch_relation
    dpg_contacts_linked_to_gec_scope.includes(:gec_voter, :village, :precinct).order(:last_name, :first_name, :id)
  end

  def each_ordered_dpg_gec_mismatch_batch(batch_size: 100)
    offset = 0
    loop do
      batch = dpg_gec_mismatch_relation.offset(offset).limit(batch_size).to_a
      break if batch.empty?

      yield batch
      offset += batch_size
    end
  end

  def dpg_gec_mismatch_headers
    [
      "Contact ID",
      "GEC Voter ID",
      "Last Name",
      "First Name",
      "Phone",
      "Email",
      "DPG Address",
      "GEC Address",
      "DPG Village",
      "GEC Village",
      "DPG Precinct",
      "GEC Precinct",
      "GEC Voter Reg #",
      "Mismatch Type",
      "Suggested Action",
      "Support Status",
      "Volunteer Status",
      "Last Contact Method",
      "Last Contact Outcome",
      "Last Contact Date",
      "Last Contact Note"
    ]
  end

  def dpg_gec_mismatch_values(supporter, latest_contact_attempt: nil)
    voter = supporter.gec_voter
    mismatch_types = dpg_gec_mismatch_types(supporter)
    [
      supporter.id,
      voter&.id,
      supporter.last_name,
      supporter.first_name,
      supporter.contact_number,
      supporter.email,
      supporter.street_address,
      voter&.address,
      supporter.village&.name,
      voter&.village_name,
      supporter.precinct&.number,
      voter&.precinct_number,
      voter&.voter_registration_number,
      mismatch_types.join(", "),
      dpg_gec_mismatch_suggested_action(types: mismatch_types),
      supporter.support_status&.humanize,
      supporter.volunteer_status&.humanize,
      latest_contact_attempt&.channel&.humanize,
      latest_contact_attempt&.outcome&.humanize,
      format_date(latest_contact_attempt&.recorded_at),
      latest_contact_attempt&.note
    ]
  end

  def dpg_gec_mismatch_types(supporter)
    voter = supporter.gec_voter
    return [] unless voter

    types = []
    types << "Village" if supporter.village&.name.present? && voter.village_name.present? && supporter.village.name.casecmp?(voter.village_name) == false
    types << "Precinct" if supporter.precinct&.number.present? && voter.precinct_number.present? && supporter.precinct.number.to_s.casecmp?(voter.precinct_number.to_s) == false
    types << "Address" if address_mismatch?(supporter, voter)
    types
  end

  def address_mismatch?(supporter, voter)
    return false if supporter.street_address.blank? || voter.address.blank?

    dpg_key = AddressNormalizer.canonical_address(supporter.street_address, village_name: supporter.village&.name)
    gec_key = AddressNormalizer.canonical_address(voter.address, village_name: voter.village_name)
    dpg_key.present? && gec_key.present? && dpg_key != gec_key
  end

  def dpg_gec_mismatch_suggested_action(types:)
    actions = []
    actions << "Confirm whether DPG contact address/village needs updating" if (types & [ "Address", "Village" ]).any?
    actions << "Review precinct assignment before field or Election Day work" if types.include?("Precinct")
    actions.presence&.join("; ") || "Review linked GEC record"
  end

  def cross_reference_suggested_action(supporter, status_label:, include_match_note:)
    return "Review possible GEC candidates and confirm the correct voter" if include_match_note
    return "Use official GEC voter fields for voter-file reporting; keep DPG-entered fields visible" if status_label == "Linked to GEC"
    return "Search/link GEC voter or follow up for registration help" if supporter.needs_voter_registration_help || supporter.registered_voter_status != "yes"

    "Search/link GEC voter or keep in manual review"
  end

  def source_label(supporter)
    supporter.attribution_method.presence&.humanize || supporter.source.presence&.humanize
  end

  def gec_voter_cross_reference_values(voter)
    [
      voter.id,
      voter.last_name,
      voter.first_name,
      format_date(voter.dob),
      voter.birth_year,
      voter.address,
      voter.village_name,
      voter.precinct_number,
      voter.voter_registration_number,
      format_date(voter.gec_list_date),
      "No linked DPG contact"
    ]
  end

  def empty_report(name, message)
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Info") do |sheet|
      sheet.add_row [ message ]
    end
    { package: package, filename: "#{name}-#{date_today}.xlsx" }
  end
end
