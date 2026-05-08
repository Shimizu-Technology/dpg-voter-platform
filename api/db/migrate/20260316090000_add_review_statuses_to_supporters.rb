class AddReviewStatusesToSupporters < ActiveRecord::Migration[8.0]
  def up
    add_column :supporters, :review_status, :string
    add_column :supporters, :public_review_status, :string
    add_column :supporters, :reviewed_at, :datetime
    add_column :supporters, :reviewed_by_user_id, :bigint
    add_column :supporters, :public_reviewed_at, :datetime
    add_column :supporters, :public_reviewed_by_user_id, :bigint

    add_index :supporters, :review_status
    add_index :supporters, :public_review_status
    add_index :supporters, :reviewed_by_user_id
    add_index :supporters, :public_reviewed_by_user_id

    execute <<~SQL.squish
      UPDATE supporters
      SET
        review_status = CASE
          WHEN source IN ('public_signup', 'qr_signup') AND intake_status = 'pending_public_review' THEN 'pending'
          ELSE 'approved'
        END,
        public_review_status = CASE
          WHEN source IN ('public_signup', 'qr_signup') AND intake_status = 'pending_public_review' THEN 'pending'
          WHEN source IN ('public_signup', 'qr_signup') THEN 'approved'
          ELSE 'not_applicable'
        END
    SQL

    change_column_default :supporters, :review_status, from: nil, to: "pending"
    change_column_default :supporters, :public_review_status, from: nil, to: "not_applicable"
    change_column_null :supporters, :review_status, false
    change_column_null :supporters, :public_review_status, false
  end

  def down
    remove_index :supporters, :public_reviewed_by_user_id
    remove_index :supporters, :reviewed_by_user_id
    remove_index :supporters, :public_review_status
    remove_index :supporters, :review_status

    remove_column :supporters, :public_reviewed_by_user_id
    remove_column :supporters, :public_reviewed_at
    remove_column :supporters, :reviewed_by_user_id
    remove_column :supporters, :reviewed_at
    remove_column :supporters, :public_review_status
    remove_column :supporters, :review_status
  end
end
