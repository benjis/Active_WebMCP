# frozen_string_literal: true

# Separate Rails process: changing reload mode must not affect the test suite.
ENV["RAILS_ENV"] = "development"
require_relative "../dummy/config/environment"
raise "Reloading must be enabled for this check" unless Rails.application.config.reloading_enabled?

session = ActionDispatch::Integration::Session.new(Rails.application)
session.get("/gem/cross")
raise "Initial render failed" unless session.response.status == 200

before = HotelsController
before_definition = before.webmcp_definitions.fetch("search_hotels")
before_write = FavouritesController
before_write_definition = before_write.webmcp_definitions.fetch("add_favourite")
before.webmcp_tool :search, name: "reload_only_probe", description: "Temporary reload probe",
                            route: :search_hotels, method: :get
Rails.application.reloader.reload!
raise "Controller was not reloaded" if HotelsController.equal?(before)
if HotelsController.webmcp_definitions.fetch("search_hotels").equal?(before_definition)
  raise "Definitions were retained"
end
raise "POST controller was retained" if FavouritesController.equal?(before_write)
if FavouritesController.webmcp_definitions.fetch("add_favourite").equal?(before_write_definition)
  raise "POST definition was retained"
end
raise "Stale declaration survived reload" if HotelsController.webmcp_definitions.key?("reload_only_probe")

session.get("/gem/cross")
raise "Reloaded render failed" unless session.response.status == 200

data = JSON.parse(Nokogiri::HTML(session.response.body).at_css("script[data-active-webmcp]").text)
raise "Wrong selection after reload" unless data.map { |tool| tool.fetch("name") } == ["search_hotels"]
raise "Wrong endpoint after reload" unless data[0].fetch("endpoint").fetch("path") == "/hotels/search"

3.times do
  Rails.application.reloader.reload!
  read = HotelsController.webmcp_definitions.fetch("search_hotels")
  write = FavouritesController.webmcp_definitions.fetch("add_favourite")
  raise "Wrong read definition after reload" unless [read.route, read.method] == %w[search_hotels GET]
  raise "Wrong write definition after reload" unless [write.route, write.method] == %w[favourites POST]
end
puts "Controller replaced, definitions rebuilt, cross-controller selection rendered: PASS"
puts "POST definitions rebuilt across repeated reloads; removed declaration absent: PASS"
