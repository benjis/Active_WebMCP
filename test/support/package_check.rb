# frozen_string_literal: true

require File.join(ARGV.shift, "config/environment")
require "rspec/autorun"
require "digest"
require_relative "native_browser"

RSpec.describe "Packaged artifact" do
  include Capybara::DSL
  include NativeBrowserSupport

  before do
    Favourite.delete_all
    ResponseGate.reset
    @gates = []
  end

  after do
    @gates.each(&:release)
    ResponseGate.reset
    Capybara.reset_sessions!
  end

  def expect_tools(expected)
    result = native(<<~JS)
      const expected = #{expected.sort.to_json}, deadline = performance.now() + 5000;
      let names;
      do {
        names = (await document.modelContext.getTools()).map(t => t.name).sort();
        if (JSON.stringify(names) === JSON.stringify(expected)) return names;
        await new Promise(resolve => setTimeout(resolve, 20));
      } while (performance.now() < deadline);
      return names;
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq(expected.sort)
  end

  def envelope(name, **input)
    result = invoke(name, input)
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    value = JSON.parse(result.fetch("value"))
    expect(value.keys.sort).to eq(%w[data error httpStatus status])
    value
  end

  def login(identity = "Alice")
    click_button "Fixture #{identity}"
    expect(page).to have_selector("#identity", exact_text: identity.downcase)
    expect_tools %w[search_hotels add_favourite]
  end

  it "installed_code_and_fingerprinted_assets_come_from_the_built_gem" do
    gem = Gem.loaded_specs.fetch("active_webmcp")
    expect(gem.version.to_s).to eq(ENV.fetch("ACTIVE_WEBMCP_PACKAGE_VERSION"))
    expect(gem.full_gem_path.start_with?("#{File.join(ENV.fetch('ACTIVE_WEBMCP_PACKAGE_HOME'), 'gems')}/")).to be_truthy
    source = ActiveWebMCP::Controller::ClassMethods.instance_method(:webmcp_tool).source_location.first
    expect(source.start_with?("#{gem.full_gem_path}/")).to(be_truthy, "Loaded a checkout instead of the installed artifact")
    expect(Rails.env.production?).to be_truthy
    expect(Rails.application.config.eager_load).to be_truthy
    expect(Rails.application.config.assets.server).not_to be_truthy
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get "/"
    expect(session.response.status).to eq(200)
    policy = session.response.headers.fetch("Content-Security-Policy")
    expect(policy).to include("script-src 'self' 'nonce-")
    expect(policy).not_to include("unsafe-inline")
    expect(policy).not_to include("unsafe-eval")
    imports = JSON.parse(Nokogiri::HTML(session.response.body).at_css('script[type="importmap"]').text).fetch("imports")
    manifest = JSON.parse(Rails.root.join("public/assets/.manifest.json").read)
    %w[active_webmcp active_webmcp/runtime].each do |name|
      original = File.join(gem.full_gem_path, "app/assets/javascripts", "#{name}.js")
      path = imports.fetch(name)
      expect(path).to eq("/assets/#{manifest.fetch("#{name}.js").fetch('digested_path')}")
      session.get path
      expect(session.response.status).to eq(200)
      expect(session.response.body).to eq(File.binread(original))
    end
    puts "PACKAGE_LOADED=#{gem.full_gem_path}"
  end

  it "native_search_and_turbo_selection_without_handwritten_javascript" do
    visit "/search"
    expect(page.driver.browser.capabilities.browser_version).to eq(NativeBrowserSupport::VERSION)
    expect_tools %w[search_hotels]
    metadata = native(<<~JS)
      const tool = (await document.modelContext.getTools()).find(entry => entry.name === "search_hotels");
      return { title: tool.title, annotations: tool.annotations };
    JS
    expect(metadata.fetch("ok")).to(be_truthy, metadata.inspect)
    expect(metadata.fetch("value")).to eq({ "title" => "Search hotels",
                                            "annotations" => { "readOnlyHint" => true,
                                                               "untrustedContentHint" => true } })
    result = envelope("search_hotels", destination: "Sydney")
    expect(result["status"]).to eq("completed")
    expect(result["data"]["hotels"][0]["name"]).to eq("Package Harbour Hotel")
    page.execute_script("window.packageDocument = true")
    click_link "Write page"
    expect(page).to have_current_path("/")
    expect_tools %w[search_hotels add_favourite]
    expect(page.evaluate_script("window.packageDocument")).to eq(true)
    click_link "No tools"
    expect(page).to have_current_path("/empty")
    expect_tools []
    page.go_back
    expect(page).to have_current_path("/")
    expect_tools %w[search_hotels add_favourite]
    expect(page.evaluate_script("window.packageDocument")).to eq(true)
  end

  it "native_write_has_csrf_authorization_persistence_and_no_ui_request" do
    visit "/"
    expect_tools %w[search_hotels add_favourite]
    expect(envelope("add_favourite", hotel_id: 1)["httpStatus"]).to eq(401)
    login
    expect(envelope("add_favourite", hotel_id: 2)["httpStatus"]).to eq(403)
    expect(envelope("add_favourite", hotel_id: 0)["httpStatus"]).to eq(422)
    ResponseGate.reset
    result = envelope("add_favourite", hotel_id: 1)
    expect(result).to eq({ "status" => "completed", "httpStatus" => 200,
                           "data" => { "hotel_id" => 1, "saved" => true }, "error" => nil })
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
    expect(Favourite.count).to eq(1)
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs:")
    expect(envelope("add_favourite", hotel_id: 1)["status"]).to eq("completed")
    expect(Favourite.count).to eq(1)
    visit "/"
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
    login("Bob")
    expect(envelope("add_favourite", hotel_id: 1)["httpStatus"]).to eq(403)
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs:")
    page.execute_script("document.querySelector('meta[name=\"csrf-token\"]').remove()")
    ResponseGate.reset
    expect(envelope("add_favourite", hotel_id: 1)["error"]["code"]).to eq("missing_csrf")
    expect(ResponseGate.requests).to eq([])
  end

  it "packaged_timeout_after_commit_is_unknown_and_never_resubmitted" do
    visit "/"
    login
    native(<<~JS)
      for (const block of document.querySelectorAll('[data-active-webmcp]')) {
        const definitions = JSON.parse(block.textContent);
        definitions.forEach(tool => { tool.timeoutMs = 150; });
        block.textContent = JSON.stringify(definitions);
      }
      await (await import('active_webmcp')).refresh();
      return true;
    JS
    held = ResponseGate.arm(:hold)
    @gates << held
    result = envelope("add_favourite", hotel_id: 1)
    held.wait_for_commit
    expect(result["status"]).to eq("unknown")
    expect(result["error"]["code"]).to eq("timeout")
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  it "human_search_and_favourite_with_webmcp_disabled" do
    Capybara.using_driver(:ordinary_chrome) do
      visit "/search"
      expect(page.evaluate_script("document.modelContext")).to be_nil
      fill_in "Destination", with: "Sydney", fill_options: { clear: :backspace }
      click_button "Search hotels"
      expect(page).to have_text("Package Harbour Hotel")
      visit "/"
      click_button "Fixture Alice"
      expect(page).to have_selector("#identity", exact_text: "alice")
      click_button "Favourite hotel"
      expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
      expect(Favourite.count).to eq(1)
    end
  end
end
