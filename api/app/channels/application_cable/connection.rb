# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"
require "base64"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      token = request.params[:token].presence || bearer_token
      reject_unauthorized_connection if token.blank?

      decoded = decode_clerk_jwt(token)
      clerk_id = decoded["sub"]
      self.current_user = User.find_by(clerk_id: clerk_id)
      reject_unauthorized_connection unless current_user
    rescue JWT::DecodeError, JWT::ExpiredSignature
      reject_unauthorized_connection
    end

    private

    def bearer_token
      header = request.headers["Authorization"]
      header&.split(" ")&.last
    end

    def decode_clerk_jwt(token)
      clerk_domain = extract_clerk_domain
      jwks_hash = Rails.cache.fetch("clerk_jwks:#{clerk_domain}", expires_in: 1.hour) do
        jwks_url = "https://#{clerk_domain}/.well-known/jwks.json"
        JSON.parse(Net::HTTP.get(URI(jwks_url)))
      end

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
      encoded = pk.sub(/^pk_(test|live)_/, "")
      Base64.decode64(encoded).chomp("$")
    end
  end
end
