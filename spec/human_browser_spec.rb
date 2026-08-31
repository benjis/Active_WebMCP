# frozen_string_literal: true

require "rails_helper"
require_relative "../test/support/native_browser"

RSpec.describe "HumanBrowserTest" do
  include Capybara::DSL

  after do
    Capybara.reset_sessions!
  end

  it "human_search_when_native_api_is_unavailable" do
    Capybara.using_driver(:ordinary_chrome) do
      visit "/gem"
      expect(page.driver.browser.capabilities.browser_version).to eq("153.0.8010.12")
      expect(page.evaluate_script("document.modelContext")).to be_nil
      expect(page).to have_text("generated search")
      fill_in "Destination", with: "Sydney", fill_options: { clear: :backspace }
      expect(page).to have_field("Destination", with: "Sydney")
      click_button "Search hotels"
      expect(page).to have_text("Fixture Harbour Hotel")
    end
  end

  it "human_favourite_with_and_without_webmcp" do
    %i[native_webmcp ordinary_chrome].each do |driver|
      Favourite.delete_all
      Capybara.using_driver(driver) do
        visit "/gem/write"
        click_button "Sign in as fixture Alice"
        expect(page).to have_text("fixture-alice")
        click_button "Favourite Harbour Hotel"
        expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
        expect(Favourite.where(user_id: "fixture-alice", hotel_id: 1).count).to eq(1)
      end
    end
  end
end
