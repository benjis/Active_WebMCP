# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Development/test fixture dependencies, not runtime gem dependencies.
gem "capybara"
gem "importmap-rails"
gem "propshaft"
gem "puma"
gem "rails", "8.1.3.1"
gem "selenium-webdriver"
gem "sqlite3", ">= 2.1"
gem "turbo-rails"

group :development, :test do
  gem "rspec-rails", "8.0.4"
  gem "rubocop", "1.90.0", require: false
end
