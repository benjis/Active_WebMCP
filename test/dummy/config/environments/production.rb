# frozen_string_literal: true

# Local production-mode test fixture, never a deployment configuration.
Rails.application.configure do
  config.eager_load = true
  config.enable_reloading = false
  config.consider_all_requests_local = false
  config.public_file_server.enabled = true
  config.assets.server = false
end
