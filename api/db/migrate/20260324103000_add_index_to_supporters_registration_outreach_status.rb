class AddIndexToSupportersRegistrationOutreachStatus < ActiveRecord::Migration[8.1]
  def change
    add_index :supporters, :registration_outreach_status unless index_exists?(:supporters, :registration_outreach_status)
  end
end
