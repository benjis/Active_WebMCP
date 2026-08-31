# frozen_string_literal: true

# Regression for Chrome 153's misclassified stale-document DOM read errors.
require "rails_helper"
require_relative "../test/support/native_browser"

RSpec.describe "NavigationBrowserTest" do
  include Capybara::DSL
  include NativeBrowserSupport

  it "repeated_native_browser_logins" do
    exercise_logins(:native_webmcp)
  end

  it "repeated_logins_without_webmcp" do
    exercise_logins(:ordinary_chrome)
  end

  def exercise_logins(driver)
    Capybara.using_driver(driver) do
      60.times do
        Capybara.reset_sessions!
        visit "/gem/write"
        expect(page).to have_text("Generated search and favourite")
        ResponseGate.reset
        click_button "Sign in as fixture Alice", exact: true
        expect(page).to have_text("fixture-alice")
        post_requests = ResponseGate.requests.filter { |request| request.first == "POST" }
        expect(post_requests).to(eq([["POST", "/fixture_login"]]),
                                 "Stale DOM recovery must never re-click or resubmit the login")
      end
    end
  ensure
    ResponseGate.reset
    Capybara.reset_sessions!
  end
end
