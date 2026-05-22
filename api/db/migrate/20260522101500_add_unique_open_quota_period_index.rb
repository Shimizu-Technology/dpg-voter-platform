# frozen_string_literal: true

class AddUniqueOpenQuotaPeriodIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :quota_periods,
      :status,
      unique: true,
      where: "status = 'open'",
      name: "index_quota_periods_on_single_open_status"
  end
end
