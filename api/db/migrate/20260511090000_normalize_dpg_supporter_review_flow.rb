# frozen_string_literal: true

class NormalizeDpgSupporterReviewFlow < ActiveRecord::Migration[8.1]
  BACKUP_TABLE = :dpg_supporter_review_flow_backups

  def up
    create_table BACKUP_TABLE, id: false, if_not_exists: true do |t|
      t.bigint :supporter_id, null: false, primary_key: true
      t.string :intake_status
      t.string :review_status
      t.string :public_review_status
      t.datetime :created_at, null: false
    end

    add_index BACKUP_TABLE, :supporter_id, unique: true, if_not_exists: true

    execute <<~SQL.squish
      INSERT INTO #{BACKUP_TABLE} (
        supporter_id,
        intake_status,
        review_status,
        public_review_status,
        created_at
      )
      SELECT
        id,
        intake_status,
        review_status,
        public_review_status,
        CURRENT_TIMESTAMP
      FROM supporters
      WHERE status = 'active'
        AND source IN ('public_signup', 'qr_signup', 'bulk_import', 'staff_entry')
        AND review_status <> 'rejected'
        AND public_review_status <> 'rejected'
      ON CONFLICT (supporter_id) DO NOTHING
    SQL

    execute <<~SQL.squish
      UPDATE supporters
      SET
        intake_status = 'accepted',
        review_status = 'approved',
        public_review_status = 'not_applicable',
        updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active'
        AND source IN ('public_signup', 'qr_signup', 'bulk_import', 'staff_entry')
        AND review_status <> 'rejected'
        AND public_review_status <> 'rejected'
    SQL
  end

  def down
    return unless table_exists?(BACKUP_TABLE)

    execute <<~SQL.squish
      UPDATE supporters
      SET
        intake_status = backups.intake_status,
        review_status = backups.review_status,
        public_review_status = backups.public_review_status,
        updated_at = CURRENT_TIMESTAMP
      FROM #{BACKUP_TABLE} backups
      WHERE supporters.id = backups.supporter_id
    SQL

    drop_table BACKUP_TABLE
  end
end
