# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Request isolation", type: :request do
  before { Favourite.delete_all }

  def context(identity: "alice", tenant: "north")
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.get "/gem/write"
    client.post "/fixture_login", params: { identity: identity, tenant: tenant,
                                            return_to: "gem_write", authenticity_token: token_for(client) }
    client.follow_redirect!
    expect(client.response.status).to eq(200)
    client
  end

  def token_for(client)
    Nokogiri::HTML(client.response.body).at_css('meta[name="csrf-token"]')["content"]
  end

  def manifest_for(client)
    Nokogiri::HTML(client.response.body).css("script[data-active-webmcp]").map(&:text).join
  end

  def write(client, token, id, **extra)
    client.post "/favourites", params: { hotel_id: id, **extra }, headers: { "X-CSRF-Token" => token }, as: :json
    client.response.status
  end

  it "interleaved users and tenants share only immutable definitions" do
    definition = FavouritesController.webmcp_definitions.fetch("add_favourite")
    north = context
    south = context(tenant: "south")
    bob = context(identity: "bob")
    tokens = [north, south, bob].map { |client| token_for(client) }
    expect(tokens.uniq.size).to eq(3)
    manifests = [north, south, bob].map { |client| manifest_for(client) }
    expect(manifests.uniq.size).to eq(1)
    tokens.each { |token| expect(manifests.join).not_to include(token) }
    %w[fixture-alice fixture-bob north south].each do |private_value|
      expect(manifests.join).not_to include(private_value)
    end
    expect(FavouritesController.webmcp_definitions.fetch("add_favourite")).to equal(definition)
    expect(definition.frozen?).to be_truthy
    expect(write(north, tokens[0], 1)).to eq(200)
    expect(write(south, tokens[1], 2)).to eq(200)
    expect(write(bob, tokens[2], 1)).to eq(403)
    expect(write(north, tokens[0], 2, tenant_id: "south")).to eq(403)
    expect(write(south, tokens[1], 1, tenant_id: "north")).to eq(403)
    expect(write(south, tokens[0], 2)).to(eq(422), "Another session's CSRF token must fail")
    expect(Favourite.order(:tenant_id).pluck(:tenant_id, :user_id,
                                             :hotel_id)).to eq([["north", "fixture-alice", 1],
                                                                ["south", "fixture-alice", 2]])
    [[north, "1"], [south, "2"], [bob, ""]].each do |client, ids|
      client.get "/gem/write"
      expect(Nokogiri::HTML(client.response.body).at_css("#favourites").text.strip).to eq("Favourite hotel IDs: #{ids}".strip)
    end
  end

  it "CSP permits nonce importmap but metadata needs no executable nonce" do
    get "/gem/write"
    html = Nokogiri::HTML(response.body)
    policy = response.headers.fetch("Content-Security-Policy")
    expect(policy).to include("script-src 'self' 'nonce-")
    expect(policy).not_to include("'unsafe-inline'")
    expect(policy).not_to include("'unsafe-eval'")
    nonce = html.at_css('meta[name="csp-nonce"]')["content"]
    expect(nonce).not_to be_empty
    html.css('script[type="importmap"],script[type="module"]').each { |node| expect(node["nonce"]).to eq(nonce) }
    html.css("script[data-active-webmcp]").each do |node|
      expect(node["type"]).to eq("application/json")
      expect(node["nonce"]).to be_nil
      expect(node.text).not_to include(nonce)
    end
    get "/gem/empty"
    expect(response.body).not_to include(nonce)
  end
end
