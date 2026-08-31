# frozen_string_literal: true

require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
Bundler.require(*Rails.groups)

module ActiveWebMCPDummy
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "active-webmcp-local-fixture-only-" * 4
    config.hosts = ["127.0.0.1", "localhost", "www.example.com"]
    config.action_controller.allow_forgery_protection = true
    config.action_dispatch.show_exceptions = :none
    config.active_support.deprecation = :stderr
    config.filter_parameters += %i[password authenticity_token]
  end
end
