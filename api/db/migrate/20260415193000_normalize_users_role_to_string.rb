class NormalizeUsersRoleToString < ActiveRecord::Migration[8.1]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    return unless column_exists?(:users, :role)

    role_column = connection.columns(:users).find { |column| column.name == "role" }
    return unless role_column

    if role_column.type == :integer
      add_column :users, :role_v2, :string, default: "block_leader", null: false

      say_with_time "Normalizing legacy integer-backed user roles to strings" do
        MigrationUser.reset_column_information

        MigrationUser.find_each do |user|
          normalized_role = normalized_role_for(user)
          MigrationUser.where(id: user.id).update_all(role_v2: normalized_role)
        end
      end

      remove_index :users, :role if index_exists?(:users, :role)
      remove_column :users, :role
      rename_column :users, :role_v2, :role
      add_index :users, :role unless index_exists?(:users, :role)
    elsif role_column.type == :string
      change_column_default :users, :role, from: role_column.default, to: "block_leader"
      execute <<~SQL.squish
        UPDATE users
        SET role = 'block_leader'
        WHERE role IS NULL OR role = ''
      SQL
      change_column_null :users, :role, false
      add_index :users, :role unless index_exists?(:users, :role)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "users.role string normalization should not be reversed automatically"
  end

  private

  def normalized_role_for(user)
    email = user.email.to_s.downcase
    return "campaign_admin" if bootstrap_admin_emails.include?(email)

    raw_value = user.read_attribute_before_type_cast("role")
    return raw_value if raw_value.is_a?(String) && allowed_roles.include?(raw_value)

    # We have no trustworthy legacy enum mapping in this repo for integer roles.
    # Fall back to the least-privileged campaign role for unknown legacy rows.
    "block_leader"
  end

  def bootstrap_admin_emails
    @bootstrap_admin_emails ||= begin
      defaults = [ "shimizutechnology@gmail.com" ]
      env_values = ENV.fetch("BOOTSTRAP_ADMIN_EMAILS", "")
        .split(",")
        .map { |value| value.strip.downcase }
        .reject(&:blank?)

      (defaults + env_values).uniq
    end
  end

  def allowed_roles
    @allowed_roles ||= %w[
      campaign_admin
      data_team
      district_coordinator
      village_chief
      block_leader
      poll_watcher
    ]
  end
end
