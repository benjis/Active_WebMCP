# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/deep_dup"
require "rails/engine"
require_relative "active_webmcp/version"

# Controller-defined WebMCP tools for Rails applications.
module ActiveWebMCP
  class ConfigurationError < ArgumentError; end

  def self.deep_freeze(value)
    case value
    when Hash
      value.each do |key, item|
        deep_freeze(key)
        deep_freeze(item)
      end
    when Array
      value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end
end

require_relative "active_webmcp/schema_compiler"
require_relative "active_webmcp/tool_definition"
require_relative "active_webmcp/controller"
require_relative "active_webmcp/page_helper"
require_relative "active_webmcp/engine"
