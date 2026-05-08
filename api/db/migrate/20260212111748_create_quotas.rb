class CreateQuotas < ActiveRecord::Migration[8.1]
  def change
    create_table :quotas do |t|
      t.references :village, null: true, foreign_key: true
      t.references :district, null: true, foreign_key: true
      t.integer :target_count
      t.date :target_date
      t.string :period
      t.references :campaign, null: false, foreign_key: true

      t.timestamps
    end
  end
end
