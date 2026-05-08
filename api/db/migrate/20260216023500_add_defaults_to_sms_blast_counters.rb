class AddDefaultsToSmsBlastCounters < ActiveRecord::Migration[8.1]
  def change
    change_column_default :sms_blasts, :total_recipients, from: nil, to: 0
    change_column_default :sms_blasts, :sent_count, from: nil, to: 0
    change_column_default :sms_blasts, :failed_count, from: nil, to: 0

    change_column_null :sms_blasts, :total_recipients, false, 0
    change_column_null :sms_blasts, :sent_count, false, 0
    change_column_null :sms_blasts, :failed_count, false, 0
  end
end
