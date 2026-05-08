class AddFullVoterTurnoutFoundation < ActiveRecord::Migration[8.1]
  class MigrationSupporter < ApplicationRecord
    self.table_name = "supporters"

    belongs_to :village, class_name: "AddFullVoterTurnoutFoundation::MigrationVillage", optional: true
  end

  class MigrationVillage < ApplicationRecord
    self.table_name = "villages"
  end

  class MigrationGecVoter < ApplicationRecord
    self.table_name = "gec_voters"
  end

  def up
    add_reference :supporters, :gec_voter, foreign_key: true

    change_table :gec_voters, bulk: true do |t|
      t.string :turnout_status, null: false, default: "not_yet_voted"
      t.string :turnout_source
      t.text :turnout_note
      t.datetime :turnout_updated_at
      t.bigint :turnout_updated_by_user_id
    end

    add_index :gec_voters, :turnout_status
    add_foreign_key :gec_voters, :users, column: :turnout_updated_by_user_id

    MigrationSupporter.reset_column_information
    MigrationGecVoter.reset_column_information

    say_with_time "Backfilling supporter GEC links" do
      backfill_supporter_gec_links!
    end

    say_with_time "Backfilling GEC turnout from supporter turnout" do
      backfill_gec_turnout_from_supporters!
    end
  end

  def down
    remove_foreign_key :gec_voters, column: :turnout_updated_by_user_id
    remove_index :gec_voters, :turnout_status

    change_table :gec_voters, bulk: true do |t|
      t.remove :turnout_status, :turnout_source, :turnout_note, :turnout_updated_at, :turnout_updated_by_user_id
    end

    remove_reference :supporters, :gec_voter, foreign_key: true
  end

  private

  def backfill_supporter_gec_links!
    MigrationSupporter
      .includes(:village)
      .where(verification_status: "verified", registered_voter: true, gec_voter_id: nil)
      .find_each do |supporter|
      voter = unique_current_match_for(supporter)
      next unless voter

      supporter.update_columns(gec_voter_id: voter.id, precinct_id: voter.precinct_id)
    end
  end

  def unique_current_match_for(supporter)
    first_name = supporter.first_name.to_s.strip.downcase
    last_name = supporter.last_name.to_s.strip.downcase
    village_name = supporter.village&.name.to_s.strip.downcase
    return nil if first_name.blank? || last_name.blank? || village_name.blank?

    dob_matches = MigrationGecVoter
      .where(status: "active")
      .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", first_name, last_name)
      .where("LOWER(village_name) = ?", village_name)

    if supporter.dob.present?
      exact_dob_match = dob_matches.where(dob: supporter.dob).limit(2).to_a
      return exact_dob_match.first if exact_dob_match.one?
    end

    birth_year = supporter.dob&.year
    return nil if birth_year.blank?

    birth_year_matches = dob_matches.where(birth_year: birth_year).limit(2).to_a
    return birth_year_matches.first if birth_year_matches.one?

    nil
  end

  def backfill_gec_turnout_from_supporters!
    latest_supporter_ids = MigrationSupporter
      .where.not(gec_voter_id: nil)
      .select(Arel.sql("DISTINCT ON (gec_voter_id) id"))
      .order(Arel.sql("gec_voter_id ASC, COALESCE(turnout_updated_at, updated_at) DESC, id DESC"))

    MigrationSupporter.where(id: latest_supporter_ids).find_each do |supporter|
      MigrationGecVoter.where(id: supporter.gec_voter_id).update_all(
        turnout_status: supporter.turnout_status,
        turnout_source: normalized_gec_turnout_source(supporter.turnout_source),
        turnout_note: supporter.turnout_note,
        turnout_updated_at: supporter.turnout_updated_at,
        turnout_updated_by_user_id: supporter.turnout_updated_by_user_id
      )
    end
  end

  def normalized_gec_turnout_source(source)
    return nil unless %w[poll_watcher data_team admin_override].include?(source)

    source
  end
end
