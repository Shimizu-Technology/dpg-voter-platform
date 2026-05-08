require "test_helper"

class CampaignChannelTest < ActionCable::Channel::TestCase
  test "rejects block leader subscriptions" do
    user = User.create!(
      clerk_id: "clerk-channel-leader",
      email: "channel-leader@example.com",
      name: "Channel Leader",
      role: "block_leader"
    )

    stub_connection current_user: user
    subscribe

    assert subscription.rejected?
  end

  test "allows poll watcher subscriptions" do
    user = User.create!(
      clerk_id: "clerk-channel-watcher",
      email: "channel-watcher@example.com",
      name: "Channel Watcher",
      role: "poll_watcher"
    )

    stub_connection current_user: user
    subscribe

    assert subscription.confirmed?
    assert_has_stream "campaign_updates"
  end
end
