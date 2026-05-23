require "test_helper"

class OutreachDeliveryTest < ActiveSupport::TestCase
  test "provider events do not regress status from older events" do
    user = User.create!(clerk_id: "clerk-outreach-delivery", email: "outreach-delivery@example.com", name: "Outreach Delivery", role: "district_coordinator")
    village = Village.create!(name: "Outreach Delivery Village")
    supporter = Supporter.create!(
      first_name: "Delivery",
      last_name: "Status",
      print_name: "Delivery Status",
      contact_number: "6715557600",
      email: "delivery-status@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG update", body: "Hello", initiated_by: user)
    delivered_at = Time.current
    delivery = OutreachDelivery.create!(
      channel: "email",
      email_blast: blast,
      supporter: supporter,
      recipient: supporter.email,
      provider: "resend",
      provider_message_id: "email-status",
      status: "delivered",
      last_event_at: delivered_at,
      delivered_at: delivered_at
    )

    result = delivery.mark_provider_event!(
      status: "delivery_delayed",
      occurred_at: delivered_at - 1.minute,
      metadata: { stale_event: true }
    )

    assert_equal false, result
    assert_equal "delivered", delivery.reload.status
    assert_equal delivered_at.to_i, delivery.last_event_at.to_i
    assert_nil delivery.metadata["stale_event"]
  end
end
