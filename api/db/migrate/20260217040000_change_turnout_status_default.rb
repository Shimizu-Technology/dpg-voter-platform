class ChangeTurnoutStatusDefault < ActiveRecord::Migration[8.0]
  def up
    change_column_default :supporters, :turnout_status, "not_yet_voted"
    # Update existing 'unknown' records to 'not_yet_voted'
    execute "UPDATE supporters SET turnout_status = 'not_yet_voted' WHERE turnout_status = 'unknown'"
  end

  def down
    change_column_default :supporters, :turnout_status, "unknown"
    execute "UPDATE supporters SET turnout_status = 'unknown' WHERE turnout_status = 'not_yet_voted'"
  end
end
