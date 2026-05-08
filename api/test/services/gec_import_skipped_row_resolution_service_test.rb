require "test_helper"

class GecImportSkippedRowResolutionServiceTest < ActiveSupport::TestCase
  setup do
    Village.find_or_create_by!(name: "Barrigada")
    Village.find_or_create_by!(name: "Dededo")

    @actor = User.create!(
      clerk_id: "clerk-skipped-row-#{SecureRandom.hex(4)}",
      email: "skipped-row-#{SecureRandom.hex(4)}@example.com",
      name: "Skipped Row Reviewer",
      role: "campaign_admin"
    )

    @gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_feb_2026.csv",
      import_type: "full_list",
      status: "completed"
    )
  end

  test "preview returns create action when corrected row matches no voter" do
    skipped_row = GecImportSkippedRow.create!(
      gec_import: @gec_import,
      row_number: 10,
      message: "missing first_name or last_name",
      last_name: "CRUZ",
      village_name: "Barrigada",
      birth_year: 1985,
      raw_values: [ "CRUZ, JUAN", "Barrigada", "1985" ]
    )

    result = GecImportSkippedRowResolutionService.new(
      skipped_row: skipped_row,
      actor_user: @actor,
      attributes: {
        first_name: "JUAN",
        last_name: "CRUZ",
        village_name: "Barrigada",
        birth_year: "1985"
      }
    ).preview

    assert result.success
    assert_equal "ready_to_create", result.status
    assert_equal "create", result.suggested_action
  end

  test "preview returns ambiguous when multiple candidates match" do
    2.times do |index|
      GecVoter.create!(
        first_name: "JUAN",
        last_name: "CRUZ",
        village_name: "Barrigada",
        birth_year: 1985,
        voter_registration_number: "VR-AMB-#{index}",
        gec_list_date: Date.new(2026, 1, 25),
        imported_at: 1.month.ago
      )
    end

    skipped_row = GecImportSkippedRow.create!(
      gec_import: @gec_import,
      row_number: 11,
      message: "missing first_name or last_name",
      village_name: "Barrigada",
      birth_year: 1985
    )

    result = GecImportSkippedRowResolutionService.new(
      skipped_row: skipped_row,
      actor_user: @actor,
      attributes: {
        first_name: "JUAN",
        last_name: "CRUZ",
        village_name: "Barrigada",
        birth_year: "1985"
      }
    ).preview

    refute result.success
    assert_equal "ambiguous", result.status
    assert_equal 2, result.candidate_matches.size
  end

  test "apply resolves skipped row by updating a matched voter" do
    voter = GecVoter.create!(
      first_name: "JUAN",
      last_name: "CRUZ",
      village_name: "Barrigada",
      birth_year: 1985,
      voter_registration_number: "VR100",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago
    )

    skipped_row = GecImportSkippedRow.create!(
      gec_import: @gec_import,
      row_number: 12,
      message: "missing first_name or last_name",
      village_name: "Barrigada",
      birth_year: 1985
    )

    result = GecImportSkippedRowResolutionService.new(
      skipped_row: skipped_row,
      actor_user: @actor,
      attributes: {
        first_name: "JUAN",
        last_name: "CRUZ",
        village_name: "Dededo",
        birth_year: "1985"
      },
      selected_gec_voter_id: voter.id
    ).apply!

    assert result.success
    assert_equal "resolved_updated", result.status

    skipped_row.reload
    voter.reload

    assert_equal "resolved_updated", skipped_row.resolution_status
    assert_equal @actor, skipped_row.resolved_by_user
    assert_equal voter, skipped_row.resolved_gec_voter
    assert_equal "Dededo", voter.village_name
    assert_equal "Barrigada", voter.previous_village_name
    assert_equal 1, AuditLog.where(auditable: skipped_row, action: "gec_import_skipped_row_resolved").count
  end

  test "dismiss marks skipped row without mutating voters" do
    skipped_row = GecImportSkippedRow.create!(
      gec_import: @gec_import,
      row_number: 13,
      message: "missing first_name or last_name",
      village_name: "Barrigada",
      birth_year: 1985
    )

    result = GecImportSkippedRowResolutionService.new(
      skipped_row: skipped_row,
      actor_user: @actor
    ).dismiss!

    assert result.success
    skipped_row.reload
    assert_equal "dismissed", skipped_row.resolution_status
    assert_equal "dismiss", skipped_row.resolution_action
    assert_equal @actor, skipped_row.resolved_by_user
    assert_equal 1, AuditLog.where(auditable: skipped_row, action: "gec_import_skipped_row_dismissed").count
  end
end
