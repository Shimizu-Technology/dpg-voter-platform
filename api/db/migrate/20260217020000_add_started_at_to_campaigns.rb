# frozen_string_literal: true

class AddStartedAtToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :started_at, :date

    # Backfill existing campaigns with their created_at date
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE campaigns SET started_at = created_at::date WHERE started_at IS NULL
        SQL
      end
    end
  end
end
