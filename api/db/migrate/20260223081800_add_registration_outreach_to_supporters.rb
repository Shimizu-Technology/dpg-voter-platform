class AddRegistrationOutreachToSupporters < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:supporters, :registration_outreach_status)
      add_column :supporters, :registration_outreach_status, :string
    end
    unless column_exists?(:supporters, :registration_outreach_notes)
      add_column :supporters, :registration_outreach_notes, :text
    end
    unless column_exists?(:supporters, :registration_outreach_date)
      add_column :supporters, :registration_outreach_date, :datetime
    end
  end
end
