# frozen_string_literal: true

raise "Production environment required" unless ENV.fetch("RAILS_ENV") == "production"

require File.join(ARGV.shift, "config/environment")
require "rspec/autorun"
require_relative "native_browser"

RSpec.describe "Production build" do
  include Capybara::DSL
  include NativeBrowserSupport

  after do
    Capybara.reset_sessions!
  end

  def tools
    result = native(<<~JS)
      const deadline = performance.now() + 5000;
      let names;
      do {
        names = (await document.modelContext.getTools()).map(t => t.name).sort();
        if (names.length === 2) return names;
        await new Promise(resolve => setTimeout(resolve, 20));
      } while (performance.now() < deadline);
      return names;
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq(%w[add_favourite search_hotels])
  end

  it "precompiled_files_are_served_under_strict_csp_with_native_calls" do
    expect(Rails.application.config.eager_load).to be_truthy
    expect(Rails.application.config.reloading_enabled?).not_to be_truthy
    expect(Rails.application.config.assets.server).not_to be_truthy
    manifest = JSON.parse(Rails.root.join("public/assets/.manifest.json").read)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get "/gem/write"
    expect(session.response.status).to eq(200)
    policy = session.response.headers.fetch("Content-Security-Policy")
    expect(policy).to include("script-src 'self' 'nonce-")
    expect(policy).not_to include("unsafe-inline")
    expect(policy).not_to include("unsafe-eval")
    html = Nokogiri::HTML(session.response.body)
    imports = JSON.parse(html.at_css('script[type="importmap"]').text).fetch("imports")
    %w[active_webmcp active_webmcp/runtime].each do |name|
      path = imports.fetch(name)
      entry = manifest.fetch("#{name}.js")
      # Propshaft's manifest stores the fingerprinted path under digested_path.
      expect(path).to eq("/assets/#{entry.fetch('digested_path')}")
      file = Rails.root.join("public", path.delete_prefix("/"))
      expect(file.file?).to be_truthy
      session.get path
      expect(session.response.status).to eq(200)
      expect(session.response.body).to eq(file.binread)
    end
    Favourite.delete_all
    visit "/gem/write"
    expect(page.driver.browser.capabilities.browser_version).to eq(NativeBrowserSupport::VERSION)
    tools
    # Capture violations for normal operations; no injected scripts in this check.
    page.execute_script("window.cspViolations = []; document.addEventListener('securitypolicyviolation', e => window.cspViolations.push(e.effectiveDirective)); window.productionDocument = true;")
    search = JSON.parse(invoke("search_hotels", destination: "Sydney").fetch("value"))
    expect(search["status"]).to eq("completed")
    expect(search["data"]["hotels"][0]["name"]).to eq("Fixture Harbour Hotel")
    click_button "Sign in as fixture Alice", exact: true
    expect(page).to have_selector("#identity", exact_text: "fixture-alice")
    tools
    page.execute_script("window.cspViolations = []; document.addEventListener('securitypolicyviolation', e => window.cspViolations.push(e.effectiveDirective)); window.productionDocument = true;")
    write = JSON.parse(invoke("add_favourite", hotel_id: 1).fetch("value"))
    expect(write["status"]).to eq("completed")
    expect(Favourite.count).to eq(1)
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs:")
    click_link "Turbo empty"
    expect(page).to have_current_path("/gem/empty")
    click_link "Turbo write"
    expect(page).to have_current_path("/gem/write")
    tools
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
    expect(page.evaluate_script("window.productionDocument")).to eq(true)
    expect(page.evaluate_script("window.cspViolations")).to eq([])
    csp_errors = page.driver.browser.logs.get(:browser).select do |entry|
      entry.message.match?(/Content Security Policy|Refused to (?:load|execute)|violates.*directive/i)
    end
    expect(csp_errors).to(be_empty, csp_errors.map(&:message).join("\n"))
  end

  it "human_workflows_with_native_enhancement_disabled" do
    Favourite.delete_all
    Capybara.using_driver(:ordinary_chrome) do
      visit "/gem"
      expect(page.evaluate_script("document.modelContext")).to be_nil
      fill_in "Destination", with: "Sydney", fill_options: { clear: :backspace }
      click_button "Search hotels"
      expect(page).to have_text("Fixture Harbour Hotel")
      visit "/gem/write"
      click_button "Sign in as fixture Alice", exact: true
      expect(page).to have_selector("#identity", exact_text: "fixture-alice")
      click_button "Favourite Harbour Hotel"
      expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
      expect(Favourite.count).to eq(1)
    end
  end
end
