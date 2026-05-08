# frozen_string_literal: true

# Shared audit logging helpers used across controllers that write AuditLog records.
module AuditLoggable
  extend ActiveSupport::Concern

  private

  def normalize_changed_data(changed_data)
    changed_data.each_with_object({}) do |(field, value), output|
      if value.is_a?(Array) && value.length == 2
        output[field.to_s] = { "from" => json_safe(value[0]), "to" => json_safe(value[1]) }
      else
        output[field.to_s] = { "from" => nil, "to" => json_safe(value) }
      end
    end
  end

  # Ensure values are JSON-serializable (handles TimeWithZone, BigDecimal, etc.)
  def json_safe(value)
    case value
    when ActiveSupport::TimeWithZone, Time, DateTime then value.iso8601
    when BigDecimal then value.to_f
    else value
    end
  end

  # Unified audit log writer. Override `audit_entry_mode` in controllers for custom entry_mode.
  # Pass `normalize: true` when changed_data comes from ActiveRecord `saved_changes`.
  def log_audit!(record, action:, changed_data:, entry_mode: nil, metadata: {}, normalize: false)
    auditable = record || current_user
    auditable_type = record ? record.class.name : "User"
    data = normalize ? normalize_changed_data(changed_data) : changed_data

    AuditLog.create!(
      auditable: auditable,
      auditable_type: auditable_type,
      actor_user: current_user,
      action: action,
      changed_data: data,
      metadata: {
        entry_mode: entry_mode || audit_entry_mode,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      }.compact.merge(metadata)
    )
  end

  # Override in controllers for controller-specific entry_mode
  def audit_entry_mode
    nil
  end
end
