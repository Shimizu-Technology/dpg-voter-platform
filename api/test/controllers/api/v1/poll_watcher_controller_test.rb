# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class PollWatcherControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = User.create!(
          clerk_id: "clerk-pw-admin",
          email: "pw-admin@example.com",
          name: "PW Admin",
          role: "campaign_admin"
        )
        @watcher = User.create!(
          clerk_id: "clerk-poll-watcher",
          email: "poll-watcher@example.com",
          name: "DPG Poll Watcher",
          role: "poll_watcher"
        )
        @other_watcher = User.create!(
          clerk_id: "clerk-other-poll-watcher",
          email: "other-poll-watcher@example.com",
          name: "Other Poll Watcher",
          role: "poll_watcher"
        )
        @village = Village.create!(name: "Hagatna")
        @other_village = Village.create!(name: "Yona")
        @precinct = Precinct.create!(number: "1", village: @village, polling_site: "DPG School", registered_voters: 100)
        @other_precinct = Precinct.create!(number: "2", village: @other_village, polling_site: "Other School", registered_voters: 100)
        PollWatcherPrecinctAssignment.create!(user: @watcher, precinct: @precinct, assigned_by_user: @admin)
        @gec_import = GecImport.create!(filename: "poll-watcher-current.csv", gec_list_date: Date.current, status: "completed")
        @election_event = ElectionEvent.create!(name: "Current Poll Watcher Election", election_type: "primary", election_date: Date.current, gec_import: @gec_import)
        @election_event.activate!(actor_user: @admin)

        @voter = create_voter(first_name: "Maria", last_name: "Cruz", precinct: @precinct, village: @village)
        @other_voter = create_voter(first_name: "Jose", last_name: "Santos", precinct: @other_precinct, village: @other_village)
        @supporter = Supporter.create!(
          first_name: "Maria",
          last_name: "Cruz",
          print_name: "Maria Cruz",
          contact_number: "6715550101",
          village: @village,
          precinct: @precinct,
          source: "staff_entry",
          status: "active",
          contact_classification: "active_contact"
        )
        @supporter.update_column(:gec_voter_id, @voter.id)
      end

      test "poll watcher index only returns assigned precincts" do
        get "/api/v1/poll_watcher", headers: auth_headers(@watcher)

        assert_response :success
        assert_not response.parsed_body.dig("election_day", "precinct_assignment_required")
        precinct_numbers = response.parsed_body.fetch("villages").flat_map { |v| v.fetch("precincts").map { |p| p.fetch("number") } }
        assert_equal [ "1" ], precinct_numbers
      end

      test "poll watcher cannot view unassigned strike list" do
        get "/api/v1/poll_watcher/strike_list", params: { precinct_id: @other_precinct.id }, headers: auth_headers(@watcher)

        assert_response :forbidden
        assert_equal "precinct_not_authorized", response.parsed_body.fetch("code")
      end

      test "strike list overlays linked active DPG contacts without requiring supporter status" do
        get "/api/v1/poll_watcher/strike_list", params: { precinct_id: @precinct.id }, headers: auth_headers(@watcher)

        assert_response :success
        voter_payload = response.parsed_body.fetch("voters").find { |voter| voter.fetch("id") == @voter.id }
        overlay = voter_payload.fetch("supporter_overlay")
        assert_equal 1, overlay.fetch("supporter_count")
        assert_equal [ @village.name ], overlay.fetch("village_names")
        assert_equal [ @precinct.number ], overlay.fetch("precinct_numbers")
      end

      test "index uses latest report by reported_at not by id" do
        newer_report = PollReport.create!(
          precinct: @precinct,
          user: @watcher,
          election_event: @election_event,
          voter_count: 40,
          report_type: "turnout_update",
          reported_at: 1.hour.ago
        )
        PollReport.create!(
          precinct: @precinct,
          user: @watcher,
          election_event: @election_event,
          voter_count: 10,
          report_type: "turnout_update",
          reported_at: 2.hours.ago
        )

        get "/api/v1/poll_watcher", headers: auth_headers(@watcher)

        assert_response :success
        precinct_payload = response.parsed_body.fetch("villages").first.fetch("precincts").first
        assert_equal newer_report.voter_count, precinct_payload.fetch("last_voter_count")
      end

      test "submitted poll report belongs to the current election event" do
        post "/api/v1/poll_watcher/report",
          params: { report: { precinct_id: @precinct.id, voter_count: 25, report_type: "turnout_update" } },
          headers: auth_headers(@watcher),
          as: :json

        assert_response :created
        report = PollReport.find(response.parsed_body.dig("report", "id"))
        assert_equal @election_event.id, report.election_event_id
      end

      test "poll watcher can update turnout for assigned precinct voter" do
        assert_difference -> { AuditLog.where(action: "election_turnout_updated").count }, 1 do
          patch "/api/v1/poll_watcher/strike_list/#{@voter.id}/turnout",
            params: { turnout: { precinct_id: @precinct.id, turnout_status: "voted", note: "Observed at table" } },
            headers: auth_headers(@watcher)
        end

        assert_response :success
        assert_equal "voted", @voter.reload.turnout_status
        assert_equal "poll_watcher", @voter.turnout_source
        assert_equal @watcher.id, @voter.turnout_updated_by_user_id
        assert_equal "voted", @supporter.reload.turnout_status
        assert_equal "poll_watcher", @supporter.turnout_source
        assert_equal [ "not_yet_voted", "voted" ], response.parsed_body.dig("changed", "turnout_status")
      end

      test "training turnout response reports the election scoped change without updating legacy turnout" do
        @election_event.close!(actor_user: @admin)
        training_event = ElectionEvent.create!(
          name: "Poll Watcher Training",
          election_type: "primary",
          election_date: Date.current,
          gec_import: @gec_import
        )
        training_event.start_training!(actor_user: @admin)

        patch "/api/v1/poll_watcher/strike_list/#{@voter.id}/turnout",
          params: { turnout: { precinct_id: @precinct.id, turnout_status: "voted", note: "Training checkoff" } },
          headers: auth_headers(@watcher),
          as: :json

        assert_response :success
        assert_equal [ "not_yet_voted", "voted" ], response.parsed_body.dig("changed", "turnout_status")
        assert_equal "voted", response.parsed_body.dig("voter", "turnout_status")
        assert_equal "voted", ElectionTurnoutRecord.find_by!(election_event: training_event, gec_voter: @voter).turnout_status
        assert_equal "not_yet_voted", @voter.reload.turnout_status
      end

      test "strike list external search filters election turnout before limiting matches" do
        60.times do |index|
          voter = create_voter(first_name: "Alex", last_name: "External#{format('%02d', index)}", precinct: @other_precinct, village: @other_village)
          if index < 50
            ElectionTurnoutRecord.create!(
              election_event: @election_event,
              gec_voter: voter,
              turnout_status: "voted",
              turnout_source: "admin_override",
              turnout_updated_by_user: @admin,
              turnout_updated_at: Time.current
            )
          end
        end

        get "/api/v1/poll_watcher/strike_list",
          params: { precinct_id: @precinct.id, search: "Alex", turnout_status: "not_yet_voted" },
          headers: auth_headers(@watcher)

        assert_response :success
        external_matches = response.parsed_body.fetch("external_matches")
        assert_equal 10, external_matches.size
        assert external_matches.all? { |row| row.fetch("turnout_status") == "not_yet_voted" }
      end

      test "poll watcher cannot mark voter from unassigned precinct as in-precinct turnout" do
        patch "/api/v1/poll_watcher/strike_list/#{@other_voter.id}/turnout",
          params: { turnout: { precinct_id: @precinct.id, turnout_status: "voted" } },
          headers: auth_headers(@watcher)

        assert_response :not_found
        assert_equal "not_yet_voted", @other_voter.reload.turnout_status
      end

      test "poll watcher cannot directly mark arbitrary out-of-precinct voter as observed elsewhere" do
        patch "/api/v1/poll_watcher/strike_list/#{@other_voter.id}/turnout",
          params: { turnout: { precinct_id: @precinct.id, turnout_status: "observed_elsewhere" } },
          headers: auth_headers(@watcher)

        assert_response :not_found
        assert_equal "not_yet_voted", @other_voter.reload.turnout_status
      end

      test "admin may reconcile out-of-precinct observed elsewhere status" do
        assert_difference -> { AuditLog.where(action: "election_turnout_updated").count }, 1 do
          patch "/api/v1/poll_watcher/strike_list/#{@other_voter.id}/turnout",
            params: { turnout: { precinct_id: @precinct.id, turnout_status: "observed_elsewhere", note: "Reported at table" } },
            headers: auth_headers(@admin)
        end

        assert_response :success
        assert_equal "observed_elsewhere", @other_voter.reload.turnout_status
        assert_equal "admin_override", @other_voter.turnout_source
      end

      test "unassigned poll watcher sees an explicit assignment warning and no precincts" do
        get "/api/v1/poll_watcher", headers: auth_headers(@other_watcher)

        assert_response :success
        assert response.parsed_body.dig("election_day", "precinct_assignment_required")
        assert_empty response.parsed_body.fetch("villages")
      end

      private

      def create_voter(first_name:, last_name:, precinct:, village:)
        GecVoter.create!(
          first_name: first_name,
          last_name: last_name,
          village_name: village.name,
          village: village,
          precinct: precinct,
          precinct_number: precinct.number,
          address: "123 Test Street",
          gec_list_date: Date.current,
          imported_at: Time.current,
          status: "active"
        )
      end
    end
  end
end
