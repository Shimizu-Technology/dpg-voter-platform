# frozen_string_literal: true

class AddUniqueResendIndexToOutreachDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_index :outreach_deliveries,
      :resend_of_id,
      unique: true,
      where: "resend_of_id IS NOT NULL",
      name: "index_outreach_deliveries_unique_resend_of"
  end
end
