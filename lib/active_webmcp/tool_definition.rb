# frozen_string_literal: true

module ActiveWebMCP
  # Immutable, validated declaration of one controller-backed browser tool.
  class ToolDefinition
    attr_reader :action, :name, :title, :description, :route, :method, :schema, :annotations

    def initialize(action, name:, description:, route:, method:, execution: :json, parameters: {}, title: nil,
                   read_only_hint: false, untrusted_content_hint: false)
      validate_identifier_types!(action, name, route)
      assign_identifiers(action, name, route, method)
      validate_identifiers!
      validate_options!(description, execution, title, read_only_hint, untrusted_content_hint)
      @description = description.dup.freeze
      @title = title&.dup&.freeze
      @annotations = compile_annotations(read_only_hint, untrusted_content_hint)
      @schema = SchemaCompiler.compile(parameters)
      freeze
    end

    private

    def assign_identifiers(action, name, route, method)
      @action = action.to_s.dup.freeze
      @name = name.to_s.dup.freeze
      @route = route.to_s.dup.freeze
      @method = method.to_s.upcase.freeze
    end

    def validate_identifier_types!(*values)
      return if values.all? { |value| value.is_a?(String) || value.is_a?(Symbol) }

      raise ConfigurationError, "action, name and route must be strings or symbols"
    end

    def validate_identifiers!
      unless @action.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) && @route.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
        raise ConfigurationError, "action and named route must be identifiers"
      end
      return if @name.match?(/\A[a-zA-Z0-9_.-]{1,128}\z/)

      raise ConfigurationError, "tool name must contain 1–128 ASCII letters, digits, dots, underscores or hyphens"
    end

    def validate_options!(description, execution, title, *hints)
      validate_description!(description)
      validate_title!(title)
      validate_hints!(hints)
      raise ConfigurationError, "method must be :get or :post" unless %w[GET POST].include?(@method)
      raise ConfigurationError, "only execution: :json is supported" unless execution.to_s == "json"
    end

    def validate_description!(description)
      return if description.is_a?(String) && !description.strip.empty?

      raise ConfigurationError, "tool description must be a nonempty string"
    end

    def validate_title!(title)
      return if title.nil? || (title.is_a?(String) && !title.strip.empty?)

      raise ConfigurationError, "tool title must be nil or a nonempty string"
    end

    def validate_hints!(hints)
      return if hints.all? { |hint| [true, false].include?(hint) }

      raise ConfigurationError, "tool annotation hints must be true or false"
    end

    def compile_annotations(read_only_hint, untrusted_content_hint)
      return if !read_only_hint && !untrusted_content_hint

      { readOnlyHint: read_only_hint, untrustedContentHint: untrusted_content_hint }.freeze
    end
  end
end
