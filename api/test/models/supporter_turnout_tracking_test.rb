require "test_helper"

class SupporterTurnoutTrackingTest < ActiveSupport::TestCase
  def setup
    @village = Village.create!(name: "Turnout Village")
    @watcher = User.create!(
      clerk_id: "clerk-turnout-watcher",
      email: "turnout-watcher@example.com",
      name: "Turnout Watcher",
      role: "poll_watcher"
    )
    @supporter = Supporter.create!(
      first_name: "Turnout", last_name: "Supporter", print_name: "Turnout Supporter",
      contact_number: "6715559999",
      village: @village,
      source: "staff_entry",
      status: "active"
    )
  end

  test "supporter turnout status defaults to not_yet_voted" do
    assert_equal "not_yet_voted", @supporter.turnout_status
  end

  test "supporter validates turnout status inclusion" do
    @supporter.turnout_status = "maybe"

    assert_not @supporter.valid?
    assert_includes @supporter.errors[:turnout_status], "is not included in the list"
  end

  test "supporter accepts observed elsewhere turnout status" do
    @supporter.turnout_status = "observed_elsewhere"

    assert @supporter.valid?
  end

  test "supporter accepts data team turnout source" do
    @supporter.turnout_source = "data_team"

    assert @supporter.valid?
  end

  test "supporter contact attempt validates required fields" do
    attempt = SupporterContactAttempt.new(
      supporter: @supporter,
      recorded_by_user: @watcher,
      outcome: "attempted",
      channel: "call",
      recorded_at: Time.current
    )

    assert attempt.valid?
  end

  test "supporter contact attempt rejects unsupported outcome" do
    attempt = SupporterContactAttempt.new(
      supporter: @supporter,
      recorded_by_user: @watcher,
      outcome: "left_voicemail",
      channel: "call",
      recorded_at: Time.current
    )

    assert_not attempt.valid?
    assert_includes attempt.errors[:outcome], "is not included in the list"
  end

  test "supporter contact attempt rejects unsupported channel" do
    attempt = SupporterContactAttempt.new(
      supporter: @supporter,
      recorded_by_user: @watcher,
      outcome: "attempted",
      channel: "email",
      recorded_at: Time.current
    )

    assert_not attempt.valid?
    assert_includes attempt.errors[:channel], "is not included in the list"
  end
end
