# frozen_string_literal: true

module Api
  module V1
    class LeaderboardController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_leaderboard_access!

      # GET /api/v1/leaderboard
      def index
        base_scope = scope_supporters(
          Supporter.active
            .where(attribution_method: %w[qr_self_signup staff_manual staff_scan bulk_import])
        )

        # Phase 1: SQL aggregation for counts by attribution owner
        aggregated = aggregate_by_owner(base_scope)

        sorted = aggregated.values.sort_by { |row| [ -row[:qr_signups], -row[:total_added], row[:owner_name].to_s ] }
        leaderboard = sorted.map.with_index do |row, idx|
          {
            rank: idx + 1,
            leader_code: row[:leader_code],
            owner_name: row[:owner_name],
            assigned_user_name: row[:assigned_user_name],
            assigned_user_email: row[:assigned_user_email],
            signup_count: row[:qr_signups],
            qr_signups: row[:qr_signups],
            manual_entries: row[:manual_entries],
            scan_entries: row[:scan_entries],
            import_entries: row[:import_entries],
            total_added: row[:total_added],
            village_name: row[:village_name],
            latest_signup: row[:latest_signup_at]&.iso8601
          }
        end

        totals = leaderboard.each_with_object(Hash.new(0)) do |row, acc|
          acc[:qr_signups] += row[:qr_signups]
          acc[:manual_entries] += row[:manual_entries]
          acc[:scan_entries] += row[:scan_entries]
          acc[:import_entries] += row[:import_entries]
        end

        total_qr_signups = totals[:qr_signups]
        active_leaders = leaderboard.size
        top_leader_count = leaderboard.first&.dig(:qr_signups).to_i
        total_added = totals.values.sum

        render json: {
          leaderboard: leaderboard,
          stats: {
            total_qr_signups: total_qr_signups,
            total_manual_entries: totals[:manual_entries],
            total_scan_entries: totals[:scan_entries],
            total_import_entries: totals[:import_entries],
            total_added: total_added,
            active_leaders: active_leaders,
            top_leader_signups: top_leader_count,
            # Only count leaders who actually have QR signups in the denominator
            avg_signups_per_leader: begin
              qr_leaders = leaderboard.count { |r| r[:qr_signups] > 0 }
              qr_leaders > 0 ? (total_qr_signups.to_f / qr_leaders).round(1) : 0
            end
          }
        }
      end

      private

      # SQL-based aggregation: groups supporters by owner (referral code or entered_by user)
      # and counts attribution channels via conditional aggregation.
      def aggregate_by_owner(scope)
        # Step 1: SQL aggregation. Note: .select with aliases (cnt, latest_at) are accessible
        # as virtual attributes on the returned AR objects. Intentionally merges QR + staff
        # entries under the same user key so each person gets one leaderboard row.
        # Each supporter has exactly one (referral_code_id, entered_by_user_id, attribution_method)
        # tuple, so GROUP BY won't double-count. Multiple GROUP BY rows may resolve to the same
        # owner_key, and their counts are summed via += in the grouped hash.
        rows = scope
          .select(
            "referral_code_id",
            "entered_by_user_id",
            "attribution_method",
            "COUNT(*) AS cnt",
            "MAX(supporters.created_at) AS latest_at"
          )
          .group("referral_code_id, entered_by_user_id, attribution_method")

        # Step 2: Preload referral codes + users for display
        rc_ids = rows.filter_map(&:referral_code_id).uniq
        user_ids = rows.filter_map(&:entered_by_user_id).uniq

        referral_codes = ReferralCode.where(id: rc_ids).includes(:assigned_user, :village).index_by(&:id)
        users = User.where(id: user_ids).index_by(&:id)

        grouped = {}
        rows.each do |row|
          rc = row.referral_code_id ? referral_codes[row.referral_code_id] : nil
          entry_user = row.entered_by_user_id ? users[row.entered_by_user_id] : nil
          channel = attribution_channel_for_method(row.attribution_method)
          next unless channel

          owner_key, owner_data = resolve_owner(rc, entry_user, channel)
          next if owner_key.blank?

          if grouped[owner_key].nil?
            grouped[owner_key] = owner_data.merge(
              qr_signups: 0, manual_entries: 0, scan_entries: 0,
              import_entries: 0, total_added: 0, latest_signup_at: nil
            )
          else
            # Prefer QR-derived metadata (real code + village) over staff-derived
            current = grouped[owner_key]
            if current[:leader_code]&.start_with?("staff-") && !owner_data[:leader_code]&.start_with?("staff-")
              current[:leader_code] = owner_data[:leader_code]
              current[:village_name] = owner_data[:village_name]
            end
          end

          grouped[owner_key][channel] += row.cnt.to_i
          grouped[owner_key][:total_added] += row.cnt.to_i
          latest = row.latest_at.is_a?(String) ? Time.zone.parse(row.latest_at) : row.latest_at
          current = grouped[owner_key][:latest_signup_at]
          grouped[owner_key][:latest_signup_at] = latest if current.nil? || (latest && latest > current)
        end

        grouped
      end

      def resolve_owner(referral_code, entry_user, channel)
        if channel == :qr_signups && referral_code.nil? && entry_user.nil?
          # Orphaned QR signup (referral code was deleted) — group under a catch-all
          return [
            "orphaned:qr",
            {
              leader_code: "unknown",
              owner_name: "Unlinked QR Signups",
              assigned_user_name: nil,
              assigned_user_email: nil,
              village_name: "Various"
            }
          ]
        end

        if channel == :qr_signups && referral_code
          if referral_code.assigned_user
            user = referral_code.assigned_user
            return [
              "user:#{user.id}",
              {
                leader_code: referral_code.code,
                owner_name: user.name.presence || user.email,
                assigned_user_name: user.name,
                assigned_user_email: user.email,
                village_name: referral_code.village&.name || "Unknown"
              }
            ]
          end

          return [
            "code:#{referral_code.code}",
            {
              leader_code: referral_code.code,
              owner_name: referral_code.display_name,
              assigned_user_name: nil,
              assigned_user_email: nil,
              village_name: referral_code.village&.name || "Unknown"
            }
          ]
        end

        return [ nil, {} ] unless entry_user

        [
          "user:#{entry_user.id}",
          {
            leader_code: "staff-#{entry_user.id}",
            owner_name: entry_user.name.presence || entry_user.email,
            assigned_user_name: entry_user.name,
            assigned_user_email: entry_user.email,
            village_name: "Various"
          }
        ]
      end

      def attribution_channel_for_method(method)
        case method
        when "qr_self_signup" then :qr_signups
        when "staff_manual" then :manual_entries
        when "staff_scan" then :scan_entries
        when "bulk_import" then :import_entries
        end
      end
    end
  end
end
