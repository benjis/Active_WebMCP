# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RequestsTest", type: :request do
  before { Favourite.delete_all }

  it "search reuses a route for human HTML and agent JSON" do
    get "/hotels/search", params: { destination: "Sydney" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("hotels").first.fetch("name")).to eq("Fixture Harbour Hotel")
    get "/hotels/search", params: { destination: "Sydney" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Fixture Harbour Hotel")
  end

  it "missing search input is an application validation error" do
    get "/hotels/search", as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "writes require login even with valid CSRF" do
    get "/"
    post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => csrf_token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Favourite.count).to eq(0)
  end

  it "writes require CSRF and record permission and are idempotent" do
    login
    token = csrf_token
    post "/favourites", params: { hotel_id: 1 }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => "invalid" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/favourites", params: { hotel_id: 2 }, headers: { "X-CSRF-Token" => token }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Favourite.count).to eq(0)
    2.times do
      post "/favourites", params: { hotel_id: 1 }, headers: { "X-CSRF-Token" => token }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "hotel_id" => 1, "saved" => true })
    end
    expect(Favourite.count).to eq(1)
  end

  it "human favourite submission redirects and persists" do
    login
    post "/favourites", params: { hotel_id: 1, authenticity_token: csrf_token }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("Favourite hotel IDs: 1")
  end
end
