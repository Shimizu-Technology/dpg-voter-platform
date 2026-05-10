require "test_helper"

class BootstrapAuthTestController < ApplicationController
  include Authenticatable

  def show
    authenticate_request
    return if performed?

    render json: {
      email: current_user.email,
      role: current_user.role,
      clerk_id: current_user.clerk_id
    }
  end
end

class AuthenticatableBootstrapAdminTest < ActionController::TestCase
  tests BootstrapAuthTestController

  setup do
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "show" => "bootstrap_auth_test#show" }
    @request.headers["Authorization"] = "Bearer test-token"
    @original_bootstrap_admin_emails = ENV["BOOTSTRAP_ADMIN_EMAILS"]
    @original_bootstrap_admin_role = ENV["BOOTSTRAP_ADMIN_ROLE"]
  end

  teardown do
    ENV["BOOTSTRAP_ADMIN_EMAILS"] = @original_bootstrap_admin_emails
    ENV["BOOTSTRAP_ADMIN_ROLE"] = @original_bootstrap_admin_role
  end

  test "allowlisted bootstrap admin email creates and authorizes production user" do
    ENV["BOOTSTRAP_ADMIN_EMAILS"] = "shimizutechnology@gmail.com"
    ENV["BOOTSTRAP_ADMIN_ROLE"] = "campaign_admin"
    stub_clerk_token(
      "sub" => "user_prod_bootstrap",
      "email" => "shimizutechnology@gmail.com",
      "name" => "Leon Shimizu"
    )

    get :show

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "shimizutechnology@gmail.com", payload["email"]
    assert_equal "campaign_admin", payload["role"]
    assert_equal "user_prod_bootstrap", payload["clerk_id"]

    user = User.find_by!(email: "shimizutechnology@gmail.com")
    assert_equal "campaign_admin", user.role
    assert_equal "user_prod_bootstrap", user.clerk_id
  end

  test "non allowlisted email remains blocked" do
    ENV["BOOTSTRAP_ADMIN_EMAILS"] = "shimizutechnology@gmail.com"
    stub_clerk_token(
      "sub" => "user_blocked",
      "email" => "blocked@example.com",
      "name" => "Blocked User"
    )

    get :show

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "user_not_authorized", payload["code"]
    assert_nil User.find_by(email: "blocked@example.com")
  end

  private

  def stub_clerk_token(payload)
    @controller.define_singleton_method(:decode_clerk_jwt) { |_token| payload }
  end
end
