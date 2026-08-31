# frozen_string_literal: true

# Run using the NEW app's bin/rails runner, not the fixture's application.
fixture_root = File.expand_path("../dummy", __dir__)
raise "Wrong application" if Rails.root.to_s == fixture_root

session = ActionDispatch::Integration::Session.new(Rails.application)
session.host! "localhost"
session.get("/")
raise "Page render failed: #{session.response.status}" unless session.response.status == 200

html = Nokogiri::HTML(session.response.body)
tools = html.css("script[data-active-webmcp]").flat_map { |node| JSON.parse(node.text) }
raise "Unexpected selection" unless tools.map { |t| t["name"] } == %w[search_hotels add_favourite]
raise "Initializer timeout configuration not applied" unless tools.all? { |tool| tool["timeoutMs"] == 1_250 }

token = html.at_css('meta[name="csrf-token"]')["content"]
imports = JSON.parse(html.at_css("script[type='importmap']").text).fetch("imports")
%w[active_webmcp active_webmcp/runtime].each do |name|
  session.get(imports.fetch(name))
  unless session.response.status == 200 && session.response.media_type.include?("javascript")
    raise "Packaged asset unavailable: #{name}"
  end
end
session.get(tools[0].fetch("endpoint").fetch("path"), params: { destination: "Sydney" },
                                                      headers: { "Accept" => "application/json" })
unless session.response.status == 200 && session.response.parsed_body["hotels"][0]["name"] == "Clean app Harbour Hotel"
  raise "Search failed"
end

write_path = tools.find { |tool| tool["name"] == "add_favourite" }.fetch("endpoint").fetch("path")
session.post(write_path, params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => token }, as: :json)
raise "Unauthenticated write allowed" unless session.response.status == 401

session.post("/fixture_login", params: { authenticity_token: token })
session.follow_redirect!
token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')["content"]
session.post(write_path, params: { hotel_id: 1 }, as: :json)
raise "CSRF was not enforced" unless session.response.status == 422

session.post(write_path, params: { hotel_id: 2 }, headers: { "X-CSRF-Token" => token }, as: :json)
raise "Record permission was not enforced" unless session.response.status == 403

2.times do
  session.post(write_path, params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => token }, as: :json)
  raise "Favourite failed" unless session.response.status == 200 && session.response.parsed_body == { "hotel_id" => 1,
                                                                                                      "saved" => true }
end
session.get("/")
unless Nokogiri::HTML(session.response.body).at_css("#favourites").text == "1"
  raise "Fixture favourite did not persist uniquely"
end

puts "Clean app selection, assets, JSON search, authenticated CSRF write and application idempotency: PASS"
