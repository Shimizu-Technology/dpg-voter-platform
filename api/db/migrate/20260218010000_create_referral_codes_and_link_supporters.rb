class CreateReferralCodesAndLinkSupporters < ActiveRecord::Migration[8.0]
  def up
    create_table :referral_codes do |t|
      t.string :code, null: false
      t.string :display_name, null: false
      t.references :assigned_user, null: true, foreign_key: { to_table: :users }
      t.references :created_by_user, null: true, foreign_key: { to_table: :users }
      t.references :village, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :referral_codes, :code, unique: true
    add_reference :supporters, :referral_code, null: true, foreign_key: true

    # Only backfill referral codes if both supporters and villages exist
    execute <<~SQL
      INSERT INTO referral_codes (code, display_name, village_id, active, created_at, updated_at)
      SELECT
        s.leader_code,
        s.leader_code,
        COALESCE(
          (
            SELECT s2.village_id
            FROM supporters s2
            WHERE s2.leader_code = s.leader_code AND s2.village_id IS NOT NULL
            ORDER BY s2.created_at ASC
            LIMIT 1
          ),
          (
            SELECT v.id
            FROM villages v
            ORDER BY v.id ASC
            LIMIT 1
          )
        ) AS village_id,
        TRUE,
        NOW(),
        NOW()
      FROM supporters s
      WHERE s.leader_code IS NOT NULL
        AND s.leader_code <> ''
        AND EXISTS (SELECT 1 FROM villages LIMIT 1)
      GROUP BY s.leader_code
      ON CONFLICT (code) DO NOTHING;
    SQL

    execute <<~SQL
      UPDATE supporters s
      SET referral_code_id = rc.id
      FROM referral_codes rc
      WHERE s.referral_code_id IS NULL
        AND s.leader_code = rc.code;
    SQL
  end

  def down
    remove_reference :supporters, :referral_code, foreign_key: true
    drop_table :referral_codes
  end
end
