class AddPollReportReportedAtIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :poll_reports, :reported_at, if_not_exists: true
  end
end
