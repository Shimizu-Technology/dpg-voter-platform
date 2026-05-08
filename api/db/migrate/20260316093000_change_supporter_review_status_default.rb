class ChangeSupporterReviewStatusDefault < ActiveRecord::Migration[8.0]
  def up
    change_column_default :supporters, :review_status, from: "pending", to: "approved"
  end

  def down
    change_column_default :supporters, :review_status, from: "approved", to: "pending"
  end
end
