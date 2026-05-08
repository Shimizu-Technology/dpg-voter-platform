class NormalizeDistrictRecords < ActiveRecord::Migration[8.1]
  DISTRICT_NUMBERS_BY_NAME = {
    "District 1" => 1,
    "District 2" => 2,
    "District 3" => 3,
    "District 4" => 4,
    "District 5" => 5
  }.freeze

  DISTRICT_DESCRIPTIONS = {
    1 => "Lagu 1 & 2",
    2 => "Kattan",
    3 => "Luchan",
    4 => "Haya 1",
    5 => "Haya 2"
  }.freeze

  def up
    campaign_ids = District.distinct.pluck(:campaign_id)
    has_quotas_table = defined?(Quota) && Quota.table_exists?

    campaign_ids.each do |campaign_id|
      DISTRICT_NUMBERS_BY_NAME.each do |district_name, district_number|
        candidates = District.where(campaign_id: campaign_id)
          .where("number = ? OR LOWER(name) = ?", district_number, district_name.downcase)
          .order(:id)
          .to_a
        next if candidates.empty?

        primary = candidates.find { |district| district.number == district_number } || candidates.first
        primary.update!(
          number: district_number,
          name: district_name,
          description: DISTRICT_DESCRIPTIONS[district_number]
        )

        candidates.each do |duplicate|
          next if duplicate.id == primary.id

          Village.where(district_id: duplicate.id).update_all(district_id: primary.id)
          # Delete conflicting quotas before reassigning to avoid unique constraint violations
          if has_quotas_table
            existing_quota_keys = Quota.where(district_id: primary.id).pluck(:village_id)
            Quota.where(district_id: duplicate.id, village_id: existing_quota_keys).delete_all if existing_quota_keys.any?
            Quota.where(district_id: duplicate.id).update_all(district_id: primary.id)
          end
          User.where(assigned_district_id: duplicate.id).update_all(assigned_district_id: primary.id)
          duplicate.destroy!
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "District normalization should not be automatically rolled back"
  end
end
