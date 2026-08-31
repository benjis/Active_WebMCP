# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../test/dummy/config/environment"
require "rspec/rails"
require "capybara/rspec"
require "active_support/testing/stream"

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("test/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include ActiveSupport::Testing::Stream

  config.include(Module.new do
    def csrf_token
      Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    end

    def login
      get "/"
      post "/fixture_login", params: { authenticity_token: csrf_token }
      follow_redirect!
    end
  end, type: :request)
end
