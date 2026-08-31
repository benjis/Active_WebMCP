# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Write requests", type: :request do
  before { Favourite.delete_all }

  it "write page selects POST explicitly without storing CSRF in definitions" do
    get "/gem/write"
    expect(response).to have_http_status(:success)
    tools = Nokogiri::HTML(response.body).css("script[data-active-webmcp]").flat_map { |node| JSON.parse(node.text) }
    expect(tools.map { |tool| tool["name"] }).to eq(%w[search_hotels add_favourite])
    expect(tools[1]["endpoint"]).to eq({ "path" => "/favourites", "method" => "POST" })
    expect(tools[1]["timeoutMs"]).to eq(30_000)
    expect(tools.to_json).not_to include(csrf_token)
    definition = FavouritesController.webmcp_definitions.fetch("add_favourite")
    expect(definition.instance_variables.include?(:request)).not_to be_truthy
    expect(definition.method).to eq("POST")
  end

  it "application validates numeric range independently of the browser" do
    login
    token = csrf_token
    [nil, 0, -1, "wrong", 1.5].each do |id|
      post "/favourites", params: { hotel_id: id }, headers: { "X-CSRF-Token" => token }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]["hotel_id"]).to eq(["must be a positive integer"])
    end
    expect(Favourite.count).to eq(0)
  end

  it "another authenticated identity cannot save Alice's permitted hotel" do
    get "/gem/write"
    post "/fixture_login", params: { identity: "bob", return_to: "gem_write", authenticity_token: csrf_token }
    follow_redirect!
    expect(response.body).to include("fixture-bob")
    post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => csrf_token }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Favourite.count).to eq(0)
  end

  it "session reset invalidates old CSRF and a current token permits writing" do
    get "/gem/write"
    old_token = csrf_token
    post "/fixture_login", params: { return_to: "gem_write", authenticity_token: old_token }
    follow_redirect!
    current_token = csrf_token
    post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => old_token }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(Favourite.count).to eq(0)
    post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => current_token }, as: :json
    expect(response).to have_http_status(:success)
    expect(Favourite.count).to eq(1)
  end
end
