# frozen_string_literal: true

require_relative "lib/active_webmcp/version"

Gem::Specification.new do |spec|
  spec.name = "active_webmcp"
  spec.version = ActiveWebMCP::VERSION
  spec.authors = ["zbin.song@gmail.com"]
  spec.email = ["zbin.song@gmail.com"]
  spec.summary = "Explicit controller-defined WebMCP tools for Rails pages"
  spec.description = "An experimental Rails integration for explicitly selected, same-origin GET and POST " \
                     "browser tools with normalized JSON results."
  spec.homepage = "https://github.com/benjis/Active_WebMCP"
  spec.required_ruby_version = ">= 3.3"
  spec.license = "MIT"
  # Ship runtime and root-level public guidance only, never fixtures, internal docs or profiles.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "app/**/*", "README.md", "SECURITY.md", "CHANGELOG.md", "LICENSE*"]
      .select { |path| File.file?(path) }.sort
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "actionpack", "~> 8.1.0"
  spec.add_dependency "actionview", "~> 8.1.0"
  spec.add_dependency "importmap-rails", "~> 2.2"
  spec.add_dependency "propshaft", "~> 1.3"
  spec.add_dependency "railties", "~> 8.1.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
end
