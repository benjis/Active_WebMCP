# frozen_string_literal: true

module ActiveWebMCP
  # Hooks ActiveWebMCP into Rails controllers and views.
  class Engine < ::Rails::Engine
    config.active_webmcp = ActiveSupport::OrderedOptions.new
    config.active_webmcp.timeout_ms = 30_000

    initializer "active_webmcp.controller" do
      ActiveSupport.on_load(:action_controller_base) { include ActiveWebMCP::Controller }
      ActiveSupport.on_load(:action_view) { include ActiveWebMCP::PageHelper }
    end
  end
end
