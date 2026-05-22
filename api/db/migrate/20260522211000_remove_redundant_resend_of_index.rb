# frozen_string_literal: true

class RemoveRedundantResendOfIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :outreach_deliveries,
      name: "index_outreach_deliveries_on_resend_of_id"
  end
end
