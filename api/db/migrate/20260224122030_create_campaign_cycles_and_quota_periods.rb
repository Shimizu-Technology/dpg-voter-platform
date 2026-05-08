# frozen_string_literal: true

class CreateCampaignCyclesAndQuotaPeriods < ActiveRecord::Migration[8.1]
  def change
    # A campaign cycle represents an election (e.g., "2026 Primary", "2026 General")
    create_table :campaign_cycles do |t|
      t.string :name, null: false                    # e.g., "2026 Primary Election"
      t.string :cycle_type, null: false, default: "primary" # primary, general, special
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "active" # active, completed, archived
      t.boolean :carry_forward_data, null: false, default: true # carry supporters to next cycle?
      t.integer :monthly_quota_target, default: 6000  # default monthly submission target
      t.jsonb :settings, null: false, default: {}     # flexible config (due_day, etc.)
      t.timestamps
    end

    add_index :campaign_cycles, :status
    add_index :campaign_cycles, [ :start_date, :end_date ]

    # A quota period is a submission window within a cycle (typically monthly)
    create_table :quota_periods do |t|
      t.references :campaign_cycle, null: false, foreign_key: true
      t.string :name, null: false                     # e.g., "February 2026"
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.date :due_date, null: false                   # submission deadline (default: 23rd)
      t.integer :quota_target, null: false, default: 6000
      t.string :status, null: false, default: "open"  # open, submitted, closed
      t.jsonb :submission_summary, null: false, default: {} # snapshot at submission time
      t.timestamps
    end

    add_index :quota_periods, :status
    add_index :quota_periods, :due_date
    add_index :quota_periods, [ :campaign_cycle_id, :start_date ], unique: true

    # Per-village targets within a quota period
    create_table :village_quotas do |t|
      t.references :quota_period, null: false, foreign_key: true
      t.references :village, null: false, foreign_key: true
      t.integer :target, null: false, default: 0      # village-specific target
      t.integer :submitted_count, default: 0          # cached count at submission
      t.timestamps
    end

    add_index :village_quotas, [ :quota_period_id, :village_id ], unique: true

    # Link supporters to the period they were counted in
    add_reference :supporters, :quota_period, foreign_key: true, null: true
  end
end
