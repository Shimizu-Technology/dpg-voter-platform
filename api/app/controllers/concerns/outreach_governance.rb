# frozen_string_literal: true

module OutreachGovernance
  extend ActiveSupport::Concern

  private

  def outreach_filters
    {
      "village_id" => params[:village_id],
      "registered_voter" => params[:registered_voter],
      "scoped_village_ids" => scoped_village_ids
    }
  end

  def recipient_review_required_response(count)
    render_api_error(
      message: "Review the recipient count before sending. Run a dry run, then submit recipient_reviewed=true with the matching expected_recipient_count.",
      status: :unprocessable_entity,
      code: "recipient_review_required",
      details: { current_recipient_count: count }
    )
  end
end
