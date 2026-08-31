# frozen_string_literal: true

require "rails_helper"
require_relative "../test/support/native_browser"

RSpec.describe "GemNativeBrowserTest" do
  include Capybara::DSL
  include NativeBrowserSupport

  before do
    visit "/gem"
    expect(page.driver.browser.capabilities.browser_version).to eq(NativeBrowserSupport::VERSION)
    expect(page).to have_text("generated search")
    ready = native("await (await import('active_webmcp')).refresh(); return (await document.modelContext.getTools()).map(t => t.name);")
    expect(ready.fetch("ok")).to(be_truthy, ready.inspect)
    expect(ready.fetch("value")).to eq(["search_hotels"])
  end

  after do
    Capybara.reset_sessions!
  end

  it "generated_search_uses_existing_json_action" do
    page.execute_script("performance.clearResourceTimings()")
    result = invoke("search_hotels", destination: "Sydney")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to be_a(String)
    envelope = JSON.parse(result.fetch("value"))
    expect(envelope.fetch("status")).to eq("completed")
    expect(envelope.fetch("httpStatus")).to eq(200)
    expect(envelope.fetch("error")).to be_nil
    expect(envelope.fetch("data")).to eq({ "hotels" => [{ "id" => 1, "name" => "Fixture Harbour Hotel",
                                                          "destination" => "Sydney" }] })
    expect(JSON.parse(invoke("search_hotels", destination: 7).fetch("value")).fetch("status")).to eq("failed")
    expect(JSON.parse(invoke("search_hotels", destination: "Sydney",
                                              unexpected: "blocked").fetch("value")).fetch("status")).to eq("failed")
    expect(page.evaluate_script("performance.getEntriesByType('resource').filter(e => new URL(e.name).pathname === '/hotels/search').length")).to eq(1)
  end

  it "registers_current_draft_title_and_annotations" do
    result = native(<<~JS)
      const tool = (await document.modelContext.getTools()).find(entry => entry.name === "search_hotels");
      return { title: tool.title, annotations: tool.annotations };
    JS

    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq({ "title" => "Search hotels",
                                          "annotations" => { "readOnlyHint" => true,
                                                             "untrustedContentHint" => true } })
  end

  it "reinitialization_cleanup_and_foreign_registration" do
    result = native(<<~JS)
      const runtime = await import('active_webmcp');
      await document.modelContext.registerTool({ name: "foreign", description: "Unrelated fixture tool", execute: () => ({ kept: true }) });
      const entry = JSON.parse(document.querySelector('script[type="importmap"]').textContent).imports.active_webmcp;
      await import(entry + '?repeat-initialization');
      await Promise.all([runtime.refresh(), runtime.refresh()]);
      const before = (await document.modelContext.getTools()).map(t => t.name).sort();
      document.querySelector('[data-active-webmcp]').remove();
      await runtime.refresh();
      const after = (await document.modelContext.getTools()).map(t => t.name);
      return { before, after };
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")["before"]).to eq(%w[foreign search_hotels])
    expect(result.fetch("value")["after"]).to eq(["foreign"])
    expect(JSON.parse(invoke("foreign").fetch("value"))).to eq({ "kept" => true })
  end

  it "explicit_cross_controller_selection_and_empty_page" do
    visit "/gem/cross"
    result = native("await (await import('active_webmcp')).refresh(); return (await document.modelContext.getTools()).map(t => t.name);")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq(["search_hotels"])
    expect(invoke("search_hotels", destination: "Melbourne").fetch("value")).to include("Fixture Garden Hotel")
    visit "/gem/empty"
    result = native("await (await import('active_webmcp')).refresh(); return (await document.modelContext.getTools()).map(t => t.name);")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result.fetch("value")).to eq([])
  end

  it "human_search_still_works" do
    fill_in "Destination", with: "Sydney", fill_options: { clear: :backspace }
    expect(page).to have_field("Destination", with: "Sydney")
    click_button "Search hotels"
    expect(page).to have_text("Fixture Harbour Hotel")
  end

  it "native_collision_does_not_replace_another_owner" do
    result = native(<<~JS)
      const runtime = await import('active_webmcp');
      runtime.dispose();
      await document.modelContext.getTools();
      await document.modelContext.registerTool({ name: "search_hotels", description: "Foreign owner", execute: () => ({ original: true }) });
      await runtime.refresh();
      runtime.dispose();
      const tool = (await document.modelContext.getTools()).find(t => t.name === "search_hotels");
      return await document.modelContext.executeTool(tool, '{}');
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(JSON.parse(result.fetch("value"))).to eq({ "original" => true })
  end
end
