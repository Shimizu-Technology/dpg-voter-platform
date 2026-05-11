# frozen_string_literal: true

class NormalizeDpgSupporterReviewFlow < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE supporters
      SET
        intake_status = 'accepted',
        review_status = 'approved',
        public_review_status = 'not_applicable',
        updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active'
        AND source IN ('public_signup', 'qr_signup', 'bulk_import', 'staff_entry')
        AND review_status <> 'rejected'
        AND public_review_status <> 'rejected'
    SQL
  end

  def down
    # DPG no longer uses the inherited public-review pipeline, so this data
    # normalization is intentionally not reversed.
  end
end
