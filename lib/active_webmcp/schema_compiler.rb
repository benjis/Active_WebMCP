# frozen_string_literal: true

module ActiveWebMCP
  # Compiles the supported flat parameter declarations into JSON Schema.
  class SchemaCompiler
    TYPES = %w[string integer number boolean].freeze
    OPTIONS = %w[type required description enum].freeze
    RESERVED = %w[controller action format host protocol port url origin path method script_name
                  authenticity_token _method utf8 __proto__ prototype constructor].freeze
    SAFE_INTEGER = (2**53) - 1

    def self.compile(parameters)
      raise ConfigurationError, "parameters must be a Hash" unless parameters.is_a?(Hash)

      properties = {}
      required = []
      parameters.each do |key, declaration|
        name, property, required_parameter = compile_parameter(key, declaration)
        raise ConfigurationError, "duplicate parameter: #{name}" if properties.key?(name)

        properties[name] = property
        required << name if required_parameter
      end
      ActiveWebMCP.deep_freeze({ "type" => "object", "properties" => properties,
                                 "required" => required, "additionalProperties" => false })
    end

    def self.compile_parameter(key, declaration)
      name = parameter_name(key)
      options = parameter_options(name, declaration)
      type = parameter_type(name, options)
      validate_required!(name, options)
      [name, property_schema(name, type, options), options["required"]]
    end

    def self.parameter_name(key)
      unless key.is_a?(String) || key.is_a?(Symbol)
        raise ConfigurationError,
              "parameter names must be strings or symbols"
      end

      name = key.to_s
      return name if name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) && !RESERVED.include?(name)

      raise ConfigurationError, "unsupported or reserved parameter name: #{name}"
    end

    def self.parameter_options(name, declaration)
      raise ConfigurationError, "parameter #{name} must have a declaration Hash" unless declaration.is_a?(Hash)

      options = declaration.transform_keys(&:to_s)
      return options if options.size == declaration.size && (options.keys - OPTIONS).empty?

      raise ConfigurationError, "unsupported or duplicate options for parameter #{name}"
    end

    def self.parameter_type(name, options)
      type = options["type"].to_s.dup
      return type if TYPES.include?(type)

      raise ConfigurationError, "unsupported type for parameter #{name}"
    end

    def self.validate_required!(name, options)
      return unless options.key?("required") && ![true, false].include?(options["required"])

      raise ConfigurationError, "required must be a boolean for parameter #{name}"
    end

    def self.property_schema(name, type, options)
      property = { "type" => type }
      property["description"] = description(name, options) if options.key?("description")
      property["enum"] = enum_values(name, type, options) if options.key?("enum")
      property
    end

    def self.description(name, options)
      value = options["description"]
      raise ConfigurationError, "description must be a string for parameter #{name}" unless value.is_a?(String)

      value.dup
    end

    def self.enum_values(name, type, options)
      values = options["enum"]
      valid = values.is_a?(Array) && !values.empty? && values.all? { |value| valid_value?(type, value) }
      raise ConfigurationError, "enum must contain values matching the type for parameter #{name}" unless valid

      values.deep_dup.uniq
    end

    def self.valid_value?(type, value)
      case type
      when "string" then value.is_a?(String)
      when "boolean" then [true, false].include?(value)
      when "integer" then value.is_a?(Integer) && value.abs <= SAFE_INTEGER
      when "number" then valid_number?(value)
      end
    end

    def self.valid_number?(value)
      (value.is_a?(Integer) || value.is_a?(Float)) && value.finite? &&
        (!value.is_a?(Integer) || value.abs <= SAFE_INTEGER)
    end
  end
end
