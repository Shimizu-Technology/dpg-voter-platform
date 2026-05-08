# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"

module Authenticatable
  extend ActiveSupport::Concern

  private

  def authenticate_request
    if Rails.env.test? && request.headers["X-Test-User-Id"].present?
      @current_user = User.find_by(id: request.headers["X-Test-User-Id"])
      unless @current_user
        render_api_error(
          message: "Invalid test user",
          status: :unauthorized,
          code: "invalid_test_user"
        )
      end
      return
    end

    token = extract_token
    unless token
      render_api_error(
        message: "Authorization token required",
        status: :unauthorized,
        code: "authorization_token_required"
      )
      return
    end

    begin
      decoded = decode_clerk_jwt(token)
      clerk_id = decoded["sub"]
      token_email = extract_token_email(decoded)
      token_name = extract_token_name(decoded)

      @current_user = User.find_by(clerk_id: clerk_id)

      if @current_user.nil? && (token_email.blank? || token_name.blank?)
        profile = fetch_clerk_profile(clerk_id)
        token_email ||= profile[:email]
        token_name ||= profile[:name]
      end

      @current_user ||= find_or_link_user_by_email(clerk_id: clerk_id, token_email: token_email, token_name: token_name)

      if @current_user && token_name.present? && @current_user.name != token_name
        @current_user.update(name: token_name)
      end

      # Block unauthorized users — only pre-created users can access the app
      unless @current_user
        # SECURITY: Never auto-provision users. Admins must create users via the Users page.
        # The AUTO_PROVISION_USERS env var is kept for development only.
        auto_provision = Rails.env.development? && ActiveModel::Type::Boolean.new.cast(ENV.fetch("AUTO_PROVISION_USERS", "false"))

        Rails.logger.warn("[Auth] BLOCKED: Unauthorized user attempted access — clerk_id=#{clerk_id} email=#{token_email} env=#{Rails.env}")

        unless auto_provision
          render_api_error(
            message: "User is not authorized for this application",
            status: :forbidden,
            code: "user_not_authorized"
          )
          return
        end

        @current_user = User.create!(
          clerk_id: clerk_id,
          email: token_email || "#{clerk_id}@clerk.dev",
          name: token_name || "New User",
          role: "block_leader"
        )
      end
    rescue JWT::DecodeError => e
      render_api_error(
        message: "Invalid token: #{e.message}",
        status: :unauthorized,
        code: "invalid_token"
      )
    rescue JWT::ExpiredSignature
      render_api_error(
        message: "Token expired",
        status: :unauthorized,
        code: "token_expired"
      )
    end
  end

  def current_user
    @current_user
  end

  def require_admin!
    unless current_user&.admin?
      render_api_error(
        message: "Admin access required",
        status: :forbidden,
        code: "admin_access_required"
      )
    end
  end

  def require_user_manager!
    unless can_manage_users?
      render_api_error(
        message: "User management access required",
        status: :forbidden,
        code: "user_management_access_required"
      )
    end
  end

  def require_data_ops_access!
    return if can_access_data_team?

    render_api_error(
      message: "Data Ops access required",
      status: :forbidden,
      code: "data_ops_access_required"
    )
  end

  def require_reports_access!
    return if can_access_reports?

    render_api_error(
      message: "Reports access required",
      status: :forbidden,
      code: "reports_access_required"
    )
  end

  def require_supporter_import_access!
    return if can_import_supporters?

    render_api_error(
      message: "Supporter import access required",
      status: :forbidden,
      code: "supporter_import_access_required"
    )
  end

  def require_coordinator_or_above!
    unless current_user&.admin? || current_user&.data_team? || current_user&.coordinator?
      render_api_error(
        message: "Coordinator access required",
        status: :forbidden,
        code: "coordinator_access_required"
      )
    end
  end

  def require_chief_or_above!
    unless current_user&.admin? || current_user&.data_team? || current_user&.coordinator? || current_user&.chief?
      render_api_error(
        message: "Village chief access required",
        status: :forbidden,
        code: "chief_access_required"
      )
    end
  end

  def require_supporter_access!
    return if can_view_supporters?

    render_api_error(
      message: "Supporter access required",
      status: :forbidden,
      code: "supporter_access_required"
    )
  end

  def require_staff_entry_access!
    return if can_create_staff_supporters?

    render_api_error(
      message: "Staff entry access required",
      status: :forbidden,
      code: "staff_entry_access_required"
    )
  end

  def require_events_access!
    return if can_access_events?

    render_api_error(
      message: "Events access required",
      status: :forbidden,
      code: "events_access_required"
    )
  end

  def require_qr_access!
    return if can_access_qr?

    render_api_error(
      message: "QR tools access required",
      status: :forbidden,
      code: "qr_access_required"
    )
  end

  def require_leaderboard_access!
    return if can_access_leaderboard?

    render_api_error(
      message: "Leaderboard access required",
      status: :forbidden,
      code: "leaderboard_access_required"
    )
  end

  def require_war_room_access!
    return if can_access_war_room?

    render_api_error(
      message: "War room access required",
      status: :forbidden,
      code: "war_room_access_required"
    )
  end

  def require_poll_watcher_access!
    return if can_access_poll_watcher?

    render_api_error(
      message: "Poll watcher access required",
      status: :forbidden,
      code: "poll_watcher_access_required"
    )
  end

  def require_audit_logs_access!
    return if can_access_audit_logs?

    render_api_error(
      message: "Audit log access required",
      status: :forbidden,
      code: "audit_logs_access_required"
    )
  end

  def can_manage_users?
    current_user&.admin? || current_user&.coordinator?
  end

  def can_manage_configuration?
    current_user&.admin?
  end

  def can_manage_data_configuration?
    current_user&.admin? || current_user&.data_team?
  end

  def can_send_sms?
    current_user&.admin? || current_user&.coordinator?
  end

  def can_send_email?
    current_user&.admin? || current_user&.coordinator?
  end

  def can_edit_supporters?
    current_user&.admin? || current_user&.data_team? || current_user&.coordinator?
  end

  def can_view_supporters?
    current_user&.admin? || current_user&.data_team? || current_user&.coordinator? || current_user&.chief? || current_user&.leader?
  end

  def can_create_staff_supporters?
    can_view_supporters?
  end

  def can_access_events?
    current_user&.admin? || current_user&.coordinator? || current_user&.chief? || current_user&.leader?
  end

  def can_access_qr?
    current_user&.admin? || current_user&.coordinator? || current_user&.chief? || current_user&.leader?
  end

  def can_access_leaderboard?
    current_user&.admin? || current_user&.coordinator? || current_user&.chief? || current_user&.leader?
  end

  def can_access_war_room?
    current_user&.admin? || current_user&.coordinator? || current_user&.chief?
  end

  def can_access_poll_watcher?
    current_user&.admin? || current_user&.coordinator? || current_user&.poll_watcher?
  end

  def can_access_duplicates?
    current_user&.admin? || current_user&.data_team?
  end

  def can_access_audit_logs?
    current_user&.admin? || current_user&.data_team?
  end

  def can_access_data_team?
    current_user&.admin? || current_user&.data_team?
  end

  def can_access_reports?
    current_user&.admin? || current_user&.data_team? || current_user&.coordinator?
  end

  def can_import_supporters?
    can_create_staff_supporters?
  end

  def can_upload_gec?
    can_access_data_team?
  end

  def can_bulk_vet?
    can_access_data_team?
  end

  def can_review_public?
    can_access_data_team?
  end

  # Returns the village IDs this user is scoped to, or nil for full access
  def scoped_village_ids
    @scoped_village_ids ||= compute_scoped_village_ids
  end

  def compute_scoped_village_ids
    return nil if current_user&.admin? || current_user&.data_team? || (current_user&.coordinator? && current_user.assigned_district_id.blank?)

    if current_user&.coordinator? && current_user.assigned_district_id.present?
      Village.where(district_id: current_user.assigned_district_id).pluck(:id)
    elsif current_user&.assigned_village_id.present?
      [ current_user.assigned_village_id ]
    else
      [] # No assignment = no access (chiefs/leaders must have assigned village)
    end
  end

  # Apply area scoping to a supporters query
  def scope_supporters(supporters)
    ids = scoped_village_ids
    ids ? supporters.where(village_id: ids) : supporters
  end

  def manageable_roles_for_current_user
    return User::ROLES if current_user&.admin?
    return [ "village_chief", "block_leader", "poll_watcher" ] if current_user&.coordinator?

    []
  end

  def extract_token
    header = request.headers["Authorization"]
    header&.split(" ")&.last
  end

  def decode_clerk_jwt(token)
    # Decode the Clerk publishable key to get the domain
    clerk_domain = extract_clerk_domain

    jwks_hash = clerk_jwks(clerk_domain)

    # Find the matching key by kid (key ID) from the JWT header to handle key rotation
    token_header = JWT.decode(token, nil, false).last
    jwk_data = jwks_hash["keys"].find { |k| k["kid"] == token_header["kid"] } || jwks_hash["keys"].first
    jwk = JWT::JWK.import(jwk_data)

    verify_aud = ENV["CLERK_JWT_AUDIENCE"].present?
    decoded = JWT.decode(
      token,
      jwk.public_key,
      true,
      {
        algorithm: "RS256",
        verify_iss: true,
        iss: "https://#{clerk_domain}",
        verify_aud: verify_aud,
        aud: ENV["CLERK_JWT_AUDIENCE"]
      }
    )

    decoded.first
  end

  def extract_clerk_domain
    pk = ENV["CLERK_PUBLISHABLE_KEY"] || ""
    # Remove pk_test_ or pk_live_ prefix
    encoded = pk.sub(/^pk_(test|live)_/, "")
    # Base64 decode to get domain (ends with $)
    decoded = Base64.decode64(encoded).chomp("$")
    decoded
  end

  def find_or_link_user_by_email(clerk_id:, token_email:, token_name:)
    return nil if token_email.blank?

    user = User.find_by(email: token_email)
    return nil unless user

    user.update!(
      clerk_id: clerk_id,
      name: token_name || user.name
    )
    user
  end

  def extract_token_email(decoded)
    raw = decoded["email"] ||
      decoded["email_address"] ||
      decoded.dig("primary_email_address", "email_address") ||
      decoded["https://clerk.dev/email"]

    raw&.downcase
  end

  def extract_token_name(decoded)
    return decoded["name"] if decoded["name"].present?

    parts = [ decoded["first_name"], decoded["last_name"] ].compact
    return nil if parts.empty?

    parts.join(" ")
  end

  def fetch_clerk_profile(clerk_id)
    return {} if clerk_id.blank?

    secret_key = ENV["CLERK_SECRET_KEY"]
    return {} if secret_key.blank?

    Rails.cache.fetch("clerk_user_profile:#{clerk_id}", expires_in: 10.minutes) do
      uri = URI("https://api.clerk.com/v1/users/#{clerk_id}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{secret_key}"
      request["Content-Type"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Authenticatable] Clerk user lookup failed status=#{response.code}")
        next nil
      end

      payload = JSON.parse(response.body)
      full_name = payload["full_name"]
      name = if full_name.present?
        full_name
      else
        [ payload["first_name"], payload["last_name"] ].compact.join(" ").presence
      end

      primary_id = payload["primary_email_address_id"]
      email_entries = payload["email_addresses"] || []
      primary = email_entries.find { |entry| entry["id"] == primary_id } || email_entries.first

      {
        email: primary&.dig("email_address")&.downcase,
        name: name
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[Authenticatable] Clerk user lookup error: #{e.class} #{e.message}")
    {}
  end

  def clerk_jwks(clerk_domain)
    Rails.cache.fetch("clerk_jwks:#{clerk_domain}", expires_in: 1.hour) do
      jwks_url = "https://#{clerk_domain}/.well-known/jwks.json"
      JSON.parse(Net::HTTP.get(URI(jwks_url)))
    end
  end
end
