require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      clerk_id: "clerk-admin",
      email: "admin@example.com",
      name: "Admin",
      role: "campaign_admin"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator",
      email: "coordinator@example.com",
      name: "Coordinator",
      role: "district_coordinator"
    )
    @leader = User.create!(
      clerk_id: "clerk-leader",
      email: "leader@example.com",
      name: "Leader",
      role: "block_leader"
    )
  end

  test "non-manager cannot list users" do
    get "/api/v1/users", headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "user_management_access_required", payload["code"]
  end

  test "admin can list users" do
    get "/api/v1/users", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["users"].length >= 2
    assert_includes payload["roles"], "campaign_admin"
    assert_includes payload["roles"], "data_team"
  end

  test "coordinator can list only manageable users and roles" do
    get "/api/v1/users", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ "village_chief", "block_leader", "poll_watcher" ], payload["roles"]
    assert payload["users"].all? { |u| payload["roles"].include?(u["role"]) }
  end

  test "admin can precreate user by email and role" do
    assert_enqueued_with(job: SendUserInviteEmailJob) do
      post "/api/v1/users",
        params: {
          user: {
            email: "new.user@example.com",
            role: "village_chief"
          }
        },
        headers: auth_headers(@admin)
    end

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "new.user@example.com", payload.dig("user", "email")
    assert_equal "village_chief", payload.dig("user", "role")
    assert_nil payload.dig("user", "name")
  end

  test "admin can create data team user without area assignment" do
    assert_enqueued_with(job: SendUserInviteEmailJob) do
      post "/api/v1/users",
        params: {
          user: {
            email: "data.team@example.com",
            role: "data_team"
          }
        },
        headers: auth_headers(@admin)
    end

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "data_team", payload.dig("user", "role")
    assert_nil payload.dig("user", "assigned_district_id")
    assert_nil payload.dig("user", "assigned_village_id")
  end

  test "admin cannot create user with invalid email" do
    post "/api/v1/users",
      params: {
        user: {
          email: "invalid-email",
          role: "block_leader"
        }
      },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "user_create_failed", payload["code"]
    assert_includes payload["error"], "Email is invalid"
  end

  test "admin can update user role" do
    patch "/api/v1/users/#{@leader.id}",
      params: { user: { role: "poll_watcher" } },
      headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "poll_watcher", payload.dig("user", "role")
  end

  test "admin can resend invite email" do
    assert_enqueued_with(job: SendUserInviteEmailJob) do
      post "/api/v1/users/#{@leader.id}/resend_invite", headers: auth_headers(@admin)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal "Invite email queued", payload["message"]
  end

  test "coordinator can create poll watcher user" do
    assert_enqueued_with(job: SendUserInviteEmailJob) do
      post "/api/v1/users",
        params: {
          user: {
            email: "pw@example.com",
            role: "poll_watcher"
          }
        },
        headers: auth_headers(@coordinator)
    end

    assert_response :created
  end

  test "coordinator cannot create admin user" do
    post "/api/v1/users",
      params: {
        user: {
          email: "new.admin@example.com",
          role: "campaign_admin"
        }
      },
      headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "user_role_assignment_forbidden", payload["code"]
  end

  test "coordinator cannot create data team user" do
    post "/api/v1/users",
      params: {
        user: {
          email: "new.data.team@example.com",
          role: "data_team"
        }
      },
      headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "user_role_assignment_forbidden", payload["code"]
  end

  test "admin gets friendly dependency error when deleting user with foreign key records" do
    dependency_user = User.create!(
      clerk_id: "clerk-dependent-user",
      email: "dependent@example.com",
      name: "Dependent User",
      role: "block_leader"
    )

    GecImport.create!(
      gec_list_date: Date.current,
      filename: "dependency-import.csv",
      status: "completed",
      import_type: "full_list",
      uploaded_by_user: dependency_user
    )

    delete "/api/v1/users/#{dependency_user.id}", headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "user_has_dependencies", payload["code"]
    assert_includes payload["error"], "gec imports"
    assert User.exists?(dependency_user.id)
  end
end
