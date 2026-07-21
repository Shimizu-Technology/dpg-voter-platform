# frozen_string_literal: true

require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(clerk_id: "users-admin", email: "users-admin@example.com", name: "Users Admin", role: "campaign_admin")
    @campaign = Campaign.create!(name: "Democratic Party of Guam", election_year: 2026, status: "active")
    @district = District.create!(name: "Central", campaign: @campaign)
    @other_district = District.create!(name: "South", campaign: @campaign)
    @village = Village.create!(name: "Hagåtña", district: @district)
    @other_village = Village.create!(name: "Yona", district: @other_district)
    @precinct_one = Precinct.create!(number: "1", village: @village)
    @precinct_two = Precinct.create!(number: "2", village: @village)
    @outside_precinct = Precinct.create!(number: "3", village: @other_village)
  end

  test "administrator creates a poll watcher with exact precinct assignments" do
    post "/api/v1/users",
      params: {
        user: {
          email: "assigned-watcher@example.com",
          role: "poll_watcher",
          poll_watcher_precinct_ids: [ @precinct_one.id, @precinct_two.id ]
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :created
    user = User.find(response.parsed_body.dig("user", "id"))
    assert_equal [ @precinct_one.id, @precinct_two.id ], user.assigned_poll_watcher_precincts.order(:id).pluck(:id)
    assert_nil user.assigned_village_id
    assert_equal [ @precinct_one.id, @precinct_two.id ], response.parsed_body.dig("user", "poll_watcher_precinct_ids").sort
  end

  test "district coordinator cannot assign a poll watcher outside their district" do
    coordinator = User.create!(
      clerk_id: "users-coordinator",
      email: "users-coordinator@example.com",
      name: "Users Coordinator",
      role: "district_coordinator",
      assigned_district_id: @district.id
    )

    post "/api/v1/users",
      params: {
        user: {
          email: "outside-watcher@example.com",
          role: "poll_watcher",
          poll_watcher_precinct_ids: [ @outside_precinct.id ]
        }
      },
      headers: auth_headers(coordinator),
      as: :json

    assert_response :forbidden
    assert_equal "poll_watcher_precinct_forbidden", response.parsed_body["code"]
    assert_not User.exists?(email: "outside-watcher@example.com")
  end

  test "changing a poll watcher to a field role clears precinct assignments" do
    watcher = User.create!(clerk_id: "users-watcher", email: "users-watcher@example.com", name: "Users Watcher", role: "poll_watcher")
    PollWatcherPrecinctAssignment.create!(user: watcher, precinct: @precinct_one, assigned_by_user: @admin)

    patch "/api/v1/users/#{watcher.id}",
      params: {
        user: {
          role: "village_chief",
          assigned_village_id: @village.id,
          poll_watcher_precinct_ids: []
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    assert_equal "village_chief", watcher.reload.role
    assert_equal @village.id, watcher.assigned_village_id
    assert_empty watcher.poll_watcher_precinct_assignments
  end

  test "editing a poll watcher without precinct IDs preserves exact assignments" do
    watcher = User.create!(clerk_id: "profile-watcher", email: "profile-watcher@example.com", name: "Original Name", role: "poll_watcher")
    PollWatcherPrecinctAssignment.create!(user: watcher, precinct: @precinct_one, assigned_by_user: @admin)
    PollWatcherPrecinctAssignment.create!(user: watcher, precinct: @precinct_two, assigned_by_user: @admin)

    patch "/api/v1/users/#{watcher.id}",
      params: { user: { name: "Updated Name" } },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    assert_equal "Updated Name", watcher.reload.name
    assert_equal [ @precinct_one.id, @precinct_two.id ], watcher.assigned_poll_watcher_precincts.order(:id).pluck(:id)
  end
end
