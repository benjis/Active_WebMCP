# frozen_string_literal: true

require "rails_helper"
require_relative "../test/support/native_browser"

RSpec.describe "Native browser lifecycle" do
  include Capybara::DSL
  include NativeBrowserSupport

  before do
    ResponseGate.reset
    visit "/gem"
    expect(page.driver.browser.capabilities.browser_version).to eq(NativeBrowserSupport::VERSION)
    expect_tools %w[search_hotels]
    page.execute_script(<<~JS)
      window.documentMarker = 'original';
      window.lifecycleEvents = [];
      for (const name of ['turbo:before-cache', 'turbo:before-render', 'turbo:render', 'turbo:load']) {
        document.addEventListener(name, () => window.lifecycleEvents.push({ name,
          path: location.pathname, preview: document.documentElement.hasAttribute('data-turbo-preview') }));
      }
      window.addEventListener('pageshow', event => { window.restoredFromCache = event.persisted; });
    JS
  end

  after do
    ResponseGate.reset
    Capybara.reset_sessions!
  end

  # Deliberately never calls runtime.refresh: real lifecycle events must register.
  def expect_tools(expected)
    result = native(<<~JS)
      const expected = #{expected.sort.to_json};
      const deadline = performance.now() + 5000;
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

  it "turbo_transitions_and_cached_back_forward_restore_selected_tools" do
    foreign = native("await document.modelContext.registerTool({ name: 'foreign', description: 'Other owner', execute: () => ({ kept: true }) }); return true;")
    expect(foreign.fetch("ok")).to(be_truthy, foreign.inspect)
    click_link "Turbo write"
    expect(page).to have_current_path("/gem/write")
    expect_tools %w[add_favourite foreign search_hotels]
    expect(page.evaluate_script("window.documentMarker")).to eq("original")
    page.execute_script("document.body.dataset.cacheMarker = 'write-snapshot'")
    click_link "Turbo empty"
    expect(page).to have_current_path("/gem/empty")
    expect_tools %w[foreign]
    ResponseGate.reset
    page.go_back
    expect(page).to have_current_path("/gem/write")
    expect_tools %w[add_favourite foreign search_hotels]
    expect(page.evaluate_script("document.body.dataset.cacheMarker")).to eq("write-snapshot")
    expect(ResponseGate.requests).to(eq([]), "Turbo restoration must use the saved snapshot in this probe")
    page.go_forward
    expect(page).to have_current_path("/gem/empty")
    expect_tools %w[foreign]
    expect(page.evaluate_script("window.documentMarker")).to eq("original")
    expect(JSON.parse(invoke("foreign").fetch("value"))).to eq({ "kept" => true })
    events = page.evaluate_script("window.lifecycleEvents.map(e => e.name)")
    %w[turbo:before-cache turbo:before-render turbo:render turbo:load].each { |name| expect(events).to include(name) }
  end

  it "normal_document_back_forward_restores_tools" do
    click_link "Document empty"
    expect(page).to have_current_path("/gem/empty")
    expect_tools []
    expect(page.evaluate_script("window.documentMarker")).to be_nil
    page.go_back
    expect(page).to have_current_path("/gem")
    expect_tools %w[search_hotels]
    evidence = page.evaluate_script("({ persisted: window.restoredFromCache === true, marker: window.documentMarker || null, navigation: performance.getEntriesByType('navigation')[0].type })")
    puts "RESTORATION_EVIDENCE=#{evidence.to_json}"
    expect(evidence.fetch("persisted")).to(eq(true), "This gate requires actual BFCache restoration, not a reload")
    expect(evidence.fetch("marker")).to eq("original")
    expect(JSON.parse(invoke("search_hotels", destination: "Sydney").fetch("value"))["status"]).to eq("completed")
    page.go_forward
    expect(page).to have_current_path("/gem/empty")
    expect_tools []
  end

  it "cached_preview_and_final_render_do_not_keep_previous_page_tools" do
    click_link "Turbo write"
    expect(page).to have_current_path("/gem/write")
    expect_tools %w[add_favourite search_hotels]
    click_link "Turbo empty"
    expect(page).to have_current_path("/gem/empty")
    expect_tools []
    held = ResponseGate.arm(:hold, method: "GET", path: "/gem/write")
    click_link "Turbo write"
    held.wait_for_commit
    expect(page).to have_selector("html[data-turbo-preview]")
    # A preview is temporary: it must not expose tools from the departed page.
    expect_tools []
    held.release
    expect_tools %w[add_favourite search_hotels]
    expect(page).not_to have_selector("html[data-turbo-preview]")
    expect(page.evaluate_script("window.documentMarker")).to eq("original")
  ensure
    held&.release
  end

  it "strict_csp_and_escaped_metadata_work_without_inline_execution" do
    visit "/gem/escape"
    expect_tools %w[escaped_metadata]
    expect(page.all("script[data-active-webmcp]", visible: :all).size).to eq(1)
    expect(page.evaluate_script("window.metadataExecuted")).to be_nil
    result = native("return (await document.modelContext.getTools())[0].description;")
    expect(result.fetch("value")).to eq(HotelsController::ESCAPE_DESCRIPTION)
    expect(JSON.parse(invoke("escaped_metadata", destination: "Sydney").fetch("value"))["status"]).to eq("completed")
    # WebDriver evaluation bypasses CSP; a real script element must not.
    page.execute_script(<<~JS)
      window.policyViolations = [];
      document.addEventListener('securitypolicyviolation', event => window.policyViolations.push(event.effectiveDirective));
      const script = document.createElement('script');
      script.textContent = 'window.inlineExecuted=true';
      document.body.appendChild(script);
    JS
    violation = native(<<~JS)
      const deadline = performance.now() + 1000;
      while (!window.policyViolations.length && performance.now() < deadline) await new Promise(r => setTimeout(r, 10));
      return window.policyViolations;
    JS
    expect(violation.fetch("value")).to include("script-src-elem")
    expect(page.evaluate_script("window.inlineExecuted")).to be_nil
    click_link "Turbo search"
    expect(page).to have_current_path("/gem")
    expect_tools %w[search_hotels]
  end

  it "delayed_native_registration_cannot_resurrect_a_departed_selection" do
    result = native(<<~JS)
      const entry = await import('active_webmcp');
      entry.dispose();
      await document.modelContext.getTools();
      const { createRuntime, WebMCPAdapter } = await import('active_webmcp/runtime');
      const adapter = new WebMCPAdapter(document);
      const register = adapter.register.bind(adapter);
      let release, entered;
      const started = new Promise(resolve => { entered = resolve; });
      adapter.register = async (...args) => {
        const cleanup = await register(...args);
        entered();
        await new Promise(resolve => { release = resolve; });
        return cleanup;
      };
      const runtime = createRuntime({ document, location, adapter, fetch });
      const pending = runtime.refresh();
      await started;
      runtime.dispose();
      document.querySelector('[data-active-webmcp]').remove();
      const latest = runtime.refresh();
      release();
      await Promise.all([pending, latest]);
      return (await document.modelContext.getTools()).map(t => t.name);
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq([])
    click_link "Turbo write"
    expect(page).to have_current_path("/gem/write")
    expect_tools %w[add_favourite search_hotels]
  end

  it "independent_browser_sessions_keep_users_tenants_and_tokens_separate" do
    Favourite.delete_all
    contexts = [[:north, "Sign in as fixture Alice", "north", 1],
                [:south, "Sign in as fixture Alice south", "south", 2],
                [:bob, "Sign in as fixture Bob", "north", nil]]
    tokens = {}
    contexts.each do |name, button, tenant, _id|
      Capybara.using_session(name) do
        visit "/gem/write"
        click_button button, exact: true
        expect(page).to have_selector("#identity", exact_text: name == :bob ? "fixture-bob" : "fixture-alice")
        expect(page).to have_selector("#tenant", exact_text: tenant)
        expect_tools %w[add_favourite search_hotels]
        tokens[name] = page.evaluate_script("document.querySelector('meta[name=\"csrf-token\"]').content")
      end
    end
    expect(tokens.values.uniq.size).to eq(3)
    contexts.each do |name, _button, _tenant, id|
      Capybara.using_session(name) do
        result = JSON.parse(invoke("add_favourite", hotel_id: id || 1).fetch("value"))
        expect(result["httpStatus"]).to eq(id ? 200 : 403)
        if id
          denied = JSON.parse(invoke("add_favourite", hotel_id: id == 1 ? 2 : 1).fetch("value"))
          expect(denied["httpStatus"]).to eq(403)
        end
        visit "/gem/write"
        expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: #{id}".strip)
      end
    end
    Capybara.using_session(:south) do
      page.execute_script("document.querySelector('meta[name=\"csrf-token\"]').content = arguments[0]", tokens[:north])
      expect_tools %w[add_favourite search_hotels]
      expect(JSON.parse(invoke("add_favourite", hotel_id: 2).fetch("value"))["httpStatus"]).to eq(422)
      click_link "Turbo empty"
      expect(page).to have_current_path("/gem/empty")
      expect_tools []
    end
    Capybara.using_session(:north) { expect_tools %w[add_favourite search_hotels] }
    expect(Favourite.order(:tenant_id).pluck(:tenant_id, :user_id,
                                             :hotel_id)).to eq([["north", "fixture-alice", 1],
                                                                ["south", "fixture-alice", 2]])
  end

  it "turbo_cleanup_during_a_committed_write_does_not_cancel_or_resubmit" do
    Favourite.delete_all
    visit "/gem/write"
    click_button "Sign in as fixture Alice", exact: true
    expect(page).to have_selector("#identity", exact_text: "fixture-alice")
    expect_tools %w[add_favourite search_hotels]
    held = ResponseGate.arm(:hold)
    page.execute_script(<<~JS)
      window.pendingWrite = (async () => {
        const tool = (await document.modelContext.getTools()).find(t => t.name === 'add_favourite');
        return document.modelContext.executeTool(tool, '{"hotel_id":1}');
      })().then(value => ({ value }), error => ({ error: error.name }));
    JS
    held.wait_for_commit
    click_link "Turbo empty"
    expect(page).to have_current_path("/gem/empty")
    expect_tools []
    held.release
    result = native("return await window.pendingWrite;")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(JSON.parse(result.fetch("value").fetch("value"))["status"]).to eq("completed")
    post_requests = ResponseGate.requests.filter { |request| request.first == "POST" }
    expect(post_requests).to eq([["POST", "/favourites"]])
    expect(Favourite.count).to eq(1)
  ensure
    held&.release
  end
end
