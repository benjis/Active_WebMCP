# frozen_string_literal: true

module ActiveWebMCP
  # Adds immutable WebMCP tool declarations to Rails controllers.
  module Controller
    extend ActiveSupport::Concern

    included do
      class_attribute :webmcp_definitions, instance_writer: false, default: {}.freeze
    end

    class_methods do
      def webmcp_tool(action, **options)
        definition = ToolDefinition.new(action, **options)
        if webmcp_definitions.key?(definition.name)
          raise ConfigurationError, "tool already declared (possibly inherited): #{definition.name}"
        end

        self.webmcp_definitions = webmcp_definitions.merge(definition.name => definition).freeze
        definition
      rescue ArgumentError => e
        raise e if e.is_a?(ConfigurationError)

        raise ConfigurationError, "invalid webmcp_tool declaration: #{e.message}"
      end
    end
  end
end
