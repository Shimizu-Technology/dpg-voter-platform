ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "active_job/test_helper"

class ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
end

class ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  private

  def auth_headers(user)
    { "X-Test-User-Id" => user.id.to_s }
  end
end
