# frozen_string_literal: true

module ActiveWebMCP
  # Renders selected controller tools as inert JSON metadata.
  module PageHelper
    def webmcp_tools(*names, controller: self.controller.class)
      validate_controller!(controller)
      timeout = configured_timeout
      manifests = names.map(&:to_s).uniq.map { |name| manifest_for(controller, name, timeout) }
      # JSON escaping prevents </script>, HTML and Unicode separators from escaping
      # this inert data block. No user/request data is retained on controller classes.
      tag.script(ERB::Util.json_escape(manifests.to_json).html_safe,
                 type: "application/json", data: { active_webmcp: true })
    end

    private

    def validate_controller!(controller)
      valid = controller.is_a?(Class) && controller <= ActionController::Base
      valid &&= controller.respond_to?(:webmcp_definitions)
      raise ConfigurationError, "controller: must be a Rails controller class" unless valid
    end

    def configured_timeout
      timeout = Rails.application.config.active_webmcp.timeout_ms
      return timeout if timeout.is_a?(Integer) && timeout.between?(1, 2_147_483_647)

      raise ConfigurationError, "config.active_webmcp.timeout_ms must be an integer from 1 to 2147483647"
    end

    def manifest_for(controller, name, timeout)
      definition = controller.webmcp_definitions.fetch(name) do
        raise ConfigurationError, "tool not declared on #{controller.name}: #{name}"
      end
      manifest = { name: definition.name, description: definition.description, inputSchema: definition.schema,
                   timeoutMs: timeout,
                   endpoint: { path: active_webmcp_path(controller, definition), method: definition.method } }
      manifest[:title] = definition.title if definition.title
      manifest[:annotations] = definition.annotations if definition.annotations
      manifest
    end

    def active_webmcp_path(controller_class, definition)
      routes = Rails.application.routes
      route = declared_route!(routes, definition)
      validate_route!(route, controller_class, definition)
      path = public_send("#{definition.route}_path")
      validate_generated_path!(path, definition)
      validate_recognition!(routes, path, controller_class, definition)
      path
    rescue ActionController::UrlGenerationError, ActionController::RoutingError
      raise ConfigurationError, "could not resolve the declared local endpoint: #{definition.route}"
    end

    def declared_route!(routes, definition)
      routes.named_routes.get(definition.route.to_sym) ||
        raise(ConfigurationError, "named route not found: #{definition.route}")
    end

    def validate_route!(route, controller, definition)
      validate_public_action!(controller, definition)
      validate_route_target!(route, controller, definition)
      validate_static_route!(route, definition)
    end

    def validate_public_action!(controller, definition)
      return if controller.action_methods.include?(definition.action)

      raise ConfigurationError, "tool action is not public: #{definition.action}"
    end

    def validate_route_target!(route, controller, definition)
      target = [controller.controller_path, definition.action]
      return if route.defaults.values_at(:controller, :action) == target && route.verb == definition.method

      raise ConfigurationError,
            "named route does not match the declared controller, action and method: #{definition.route}"
    end

    def validate_static_route!(route, definition)
      return if (route.parts - [:format]).empty? && !route.path.spec.to_s.include?("*")

      raise ConfigurationError, "dynamic path segments and wildcard routes are not supported: #{definition.route}"
    end

    def validate_generated_path!(path, definition)
      return if path.start_with?("/") && !path.start_with?("//") && !path.match?(/[\\?#\x00-\x20]/)

      raise ConfigurationError, "route must generate a local path without query or fragment: #{definition.route}"
    end

    def validate_recognition!(routes, path, controller, definition)
      recognized = routes.recognize_path(path, method: definition.method)
      return if recognized.values_at(:controller, :action) == [controller.controller_path, definition.action]

      raise ConfigurationError, "named route is shadowed by another endpoint: #{definition.route}"
    end
  end
end
