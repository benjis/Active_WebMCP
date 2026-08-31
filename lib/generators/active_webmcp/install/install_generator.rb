# frozen_string_literal: true

require "rails/generators"

module ActiveWebMCP
  module Generators
    # Installs the importmap pins and JavaScript entrypoint into a Rails app.
    class InstallGenerator < Rails::Generators::Base
      namespace "active_webmcp:install"
      desc "Install ActiveWebMCP for Rails 8.1 with importmap and Propshaft."

      PINS = { "active_webmcp" => "active_webmcp.js", "active_webmcp/runtime" => "active_webmcp/runtime.js" }.freeze

      def validate_setup
        validate_dependencies!
        importmap_path = destination_path("config/importmap.rb")
        validate_application_files!(importmap_path)
        @missing_pins = missing_pins(File.read(importmap_path))
        detect_application_import
      end

      private

      def validate_dependencies!
        return if defined?(Propshaft) && defined?(Importmap) && Rails.version.start_with?("8.1.")

        raise Rails::Generators::Error, "ActiveWebMCP requires Rails 8.1, importmap-rails and Propshaft."
      end

      def validate_application_files!(importmap_path)
        layout_path = destination_path("app/views/layouts/application.html.erb")
        valid_layout = File.file?(layout_path) && File.read(layout_path).include?("javascript_importmap_tags")
        return if File.file?(importmap_path) && valid_layout

        raise Rails::Generators::Error,
              "Install importmap first; the application layout must use javascript_importmap_tags."
      end

      def missing_pins(source)
        PINS.reject { |name, asset| existing_pin?(source, name, asset) }
      end

      def existing_pin?(source, name, asset)
        lines = source.lines.grep_v(/^\s*#/).grep(/["']#{Regexp.escape(name)}["']/)
        return false if lines.empty?

        expected = /^\s*pin\s+["']#{Regexp.escape(name)}["']\s*,\s*to:\s*["']#{Regexp.escape(asset)}["']\s*(?:#.*)?$/
        return true if lines.one? && lines.first.match?(expected)

        raise Rails::Generators::Error, "Conflicting importmap pin for #{name}; resolve it before installing."
      end

      def detect_application_import
        application_path = destination_path("app/javascript/application.js")
        @application_exists = File.file?(application_path)
        @import_exists = @application_exists && File.read(application_path)
                                                    .match?(%r{^\s*import\s+["']active_webmcp["']\s*;?\s*(?://.*)?$})
      end

      def destination_path(relative_path)
        File.join(destination_root, relative_path)
      end

      public

      def install_assets
        @missing_pins.each do |name, asset|
          append_to_file "config/importmap.rb", "\npin #{name.inspect}, to: #{asset.inspect}\n"
        end
        unless @import_exists
          if @application_exists
            append_to_file "app/javascript/application.js", "\nimport \"active_webmcp\";\n"
          else
            create_file "app/javascript/application.js", "import \"active_webmcp\";\n"
          end
        end
        say "ActiveWebMCP installed. Declare a GET or POST tool, then select its public name with webmcp_tools."
      end
    end
  end
end
