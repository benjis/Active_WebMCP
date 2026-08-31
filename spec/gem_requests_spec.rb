# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GemRequestsTest", type: :request do
  it "selected_search_and_cross_controller_page" do
    ["/gem", "/gem/cross"].each do |path|
      get path
      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      manifests = document.css("script[type='application/json'][data-active-webmcp]")
      expect(manifests.size).to eq(1)
      data = JSON.parse(manifests.first.text)
      expect(data.map { |tool| tool["name"] }).to eq(["search_hotels"])
      expect(data.first.values_at("title", "annotations")).to eq([
                                                                   "Search hotels", { "readOnlyHint" => true, "untrustedContentHint" => true }
                                                                 ])
      importmaps = document.css("script[type='importmap']")
      expect(importmaps.size).to eq(1)
      imports = JSON.parse(importmaps.first.text).fetch("imports")
      expect(imports.fetch("active_webmcp")).to match(%r{/assets/active_webmcp-[\w-]+\.js})
      expect(imports.fetch("active_webmcp/runtime")).to match(%r{/assets/active_webmcp/runtime-[\w-]+\.js})
    end
    get "/gem/empty"
    expect(response).to have_http_status(:success)
    expect(Nokogiri::HTML(response.body).css("script[data-active-webmcp]")).to be_empty
  end

  it "existing_json_and_human_search_keep_their_contract" do
    get "/hotels/search", params: { destination: "Sydney" }, headers: { "Accept" => "application/json" }
    expect(response.parsed_body["hotels"][0]["name"]).to eq("Fixture Harbour Hotel")
    expect(response.parsed_body.key?("status")).not_to be_truthy
    get "/hotels/search", params: { destination: "Sydney" }
    expect(response).to have_http_status(:success)
    expect(Nokogiri::HTML(response.body).text).to include("Fixture Harbour Hotel")
  end
end
