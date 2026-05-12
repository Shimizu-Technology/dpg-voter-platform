# frozen_string_literal: true

class OutreachRecipientQuery
  PREVIEW_LIMIT = 25

  class << self
    def sms_scope(base_scope:, filters: {})
      apply_filters(base_scope.contacts, filters)
        .where.not(contact_number: [ nil, "" ])
        .where("TRIM(contact_number) != ''")
        .where(opt_in_text: true)
    end

    def email_scope(base_scope:, filters: {})
      apply_filters(base_scope.contacts, filters)
        .where.not(email: [ nil, "" ])
        .where(opt_in_email: true)
    end

    def preview(scope)
      {
        recipient_count: scope.count,
        recipients: scope.includes(:village).order(:last_name, :first_name).limit(PREVIEW_LIMIT).map { |supporter| recipient_json(supporter) },
        preview_limit: PREVIEW_LIMIT
      }
    end

    def reviewed?(params, expected_count:)
      ActiveModel::Type::Boolean.new.cast(params[:recipient_reviewed]) &&
        params[:expected_recipient_count].present? &&
        params[:expected_recipient_count].to_i == expected_count
    end

    private

    def apply_filters(scope, filters)
      filtered = scope
      if filters.key?("scoped_village_ids") && !filters["scoped_village_ids"].nil?
        filtered = filters["scoped_village_ids"].present? ? filtered.where(village_id: filters["scoped_village_ids"]) : filtered.none
      end
      filtered = filtered.where(village_id: filters["village_id"]) if filters["village_id"].present?
      filtered = filtered.where(registered_voter: true) if filters["registered_voter"] == "true"
      filtered
    end

    def recipient_json(supporter)
      {
        id: supporter.id,
        name: supporter.display_name,
        village_name: supporter.village&.name,
        contact_number: supporter.contact_number,
        email: supporter.email,
        registered_voter_status: supporter.registered_voter_status,
        contact_classification: supporter.contact_classification
      }
    end
  end
end
