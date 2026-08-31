# frozen_string_literal: true

require "rspec/core/rake_task"
require_relative "test/dummy/config/application"

Rails.application.load_tasks

RSpec::Core::RakeTask.new(:spec)
task default: :spec
