# frozen_string_literal: true

require "rails_helper"
require_relative "../test/support/native_browser"

RSpec.describe "Native browser writes" do
  include Capybara::DSL
  include NativeBrowserSupport

  before do
    Favourite.delete_all
    ResponseGate.reset
    @gates = []
    visit "/gem/write"
    expect(page.driver.browser.capabilities.browser_version).to eq(NativeBrowserSupport::VERSION)
    expect(page).to have_text("Generated search and favourite")
    ready = native("await (await import('active_webmcp')).refresh(); return (await document.modelContext.getTools()).map(t => t.name).sort();")
    expect(ready.fetch("ok")).to(be_truthy, ready.inspect)
    expect(ready.fetch("value")).to eq(%w[add_favourite search_hotels])
  end

  after do
    @gates.each(&:release)
    ResponseGate.reset
    Capybara.reset_sessions!
  end

  def sign_in(identity = "Alice")
    click_button "Sign in as fixture #{identity}"
    expect(page).to have_text("fixture-#{identity.downcase}")
    result = native("await (await import('active_webmcp')).refresh(); return true;")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
  end

  def favourite(id = 1)
    native_result = invoke("add_favourite", hotel_id: id)
    expect(native_result.fetch("ok")).to(be_truthy, native_result.inspect)
    result = JSON.parse(native_result.fetch("value"))
    expect(result.keys.sort).to eq(%w[data error httpStatus status])
    result
  end

  def gate(mode)
    ResponseGate.arm(mode).tap { |value| @gates << value }
  end

  def short_timeout
    result = native(<<~JS)
      for (const block of document.querySelectorAll('[data-active-webmcp]')) {
        const tools = JSON.parse(block.textContent);
        for (const tool of tools) if (tool.name === 'add_favourite') tool.timeoutMs = 150;
        block.textContent = JSON.stringify(tools);
      }
      await (await import('active_webmcp')).refresh();
      return true;
    JS
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
  end

  it "authorized_write_persists_with_no_ui_request_or_update" do
    sign_in
    ResponseGate.reset
    result = favourite
    expect(result).to eq({ "status" => "completed", "httpStatus" => 200,
                           "data" => { "hotel_id" => 1, "saved" => true }, "error" => nil })
    expect(Favourite.where(user_id: "fixture-alice", hotel_id: 1).count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs:")
    visit "/gem/write"
    expect(page).to have_selector("#favourites", exact_text: "Favourite hotel IDs: 1")
    # A second explicit invocation is application-idempotent, not a gem retry.
    expect(favourite.fetch("status")).to eq("completed")
    expect(Favourite.count).to eq(1)
  end

  it "unauthenticated_forbidden_and_application_validation_fail_safely" do
    result = favourite
    expect(result["status"]).to eq("failed")
    expect(result["httpStatus"]).to eq(401)
    sign_in
    result = favourite(2)
    expect(result["status"]).to eq("failed")
    expect(result["httpStatus"]).to eq(403)
    result = favourite(0)
    expect(result["status"]).to eq("failed")
    expect(result["httpStatus"]).to eq(422)
    expect(result["data"]["errors"]["hotel_id"]).to eq(["must be a positive integer"])
    ResponseGate.reset
    result = favourite("1")
    expect(result["error"]["code"]).to eq("invalid_parameter_type")
    expect(result["httpStatus"]).to be_nil
    expect(ResponseGate.requests).to eq([])
    expect(Favourite.count).to eq(0)
    sign_in("Bob")
    expect(favourite["httpStatus"]).to eq(403)
    expect(Favourite.count).to eq(0)
  end

  it "csrf_is_read_at_invocation_and_missing_token_prevents_dispatch" do
    sign_in
    page.execute_script(<<~JS)
      window.savedCsrfMeta = document.querySelector('meta[name="csrf-token"]').cloneNode(true);
      document.querySelector('meta[name="csrf-token"]').remove();
    JS
    ResponseGate.reset
    result = favourite
    expect(result["error"]["code"]).to eq("missing_csrf")
    expect(result["status"]).to eq("failed")
    expect(ResponseGate.requests).to eq([])
    page.execute_script(<<~JS)
      const meta = window.savedCsrfMeta.cloneNode(true);
      meta.content = 'invalid';
      document.head.appendChild(meta);
    JS
    expect(favourite["httpStatus"]).to eq(422)
    expect(Favourite.count).to eq(0)
    # No re-registration: the existing callback must use the now-current token.
    page.execute_script("document.querySelector('meta[name=\"csrf-token\"]').replaceWith(window.savedCsrfMeta)")
    expect(favourite["status"]).to eq("completed")
    expect(Favourite.count).to eq(1)
  end

  it "timeout_after_real_commit_is_unknown_without_resubmission" do
    sign_in
    short_timeout
    held = gate(:hold)
    result = favourite
    held.wait_for_commit
    expect(result["status"]).to eq("unknown")
    expect(result["error"]["code"]).to eq("timeout")
    expect(result["httpStatus"]).to be_nil
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  it "body_timeout_preserves_http_status_and_does_not_claim_rollback" do
    sign_in
    short_timeout
    held = gate(:hold_body)
    result = favourite
    held.wait_for_commit
    expect(result["status"]).to eq("unknown")
    expect(result["httpStatus"]).to eq(200)
    expect(result["error"]["code"]).to eq("timeout")
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  def start_pending_write
    page.execute_script(<<~JS)
      window.writeCancellation = new AbortController();
      window.pendingWrite = (async () => {
        const tool = (await document.modelContext.getTools()).find(t => t.name === 'add_favourite');
        return document.modelContext.executeTool(tool, '{"hotel_id":1}', { signal: window.writeCancellation.signal });
      })().then(value => ({ value }), error => ({ error: error.name }));
    JS
  end

  it "native_cancellation_may_prevent_final_envelope_delivery_after_commit" do
    sign_in
    held = gate(:hold)
    start_pending_write
    held.wait_for_commit
    result = native("window.writeCancellation.abort(); return await window.pendingWrite;")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(result["value"]["error"]).to eq("AbortError")
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  it "registration_cleanup_during_write_does_not_cancel_execution" do
    sign_in
    held = gate(:hold)
    start_pending_write
    held.wait_for_commit
    result = native("(await import('active_webmcp')).dispose(); return (await document.modelContext.getTools()).map(t => t.name);")
    expect(result.fetch("value")).to eq([])
    held.release
    result = native("return await window.pendingWrite;")
    expect(result.fetch("ok")).to(be_truthy, result.inspect)
    expect(JSON.parse(result.fetch("value").fetch("value"))["status"]).to eq("completed")
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  it "redirect_is_not_followed_even_when_the_write_was_already_committed" do
    sign_in
    gate(:redirect)
    result = favourite
    expect(result["status"]).to eq("unknown")
    expect(result["error"]["code"]).to eq("redirect_blocked")
    expect(result["httpStatus"]).to be_nil # Chrome's opaqueredirect hides 303.
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end

  it "non_json_and_invalid_json_after_commit_are_not_success" do
    sign_in
    { html: "non_json_response", invalid_json: "invalid_json" }.each do |mode, code|
      gate(mode)
      result = favourite
      expect(result["status"]).to eq("unknown")
      expect(result["httpStatus"]).to eq(200)
      expect(result["error"]["code"]).to eq(code)
      expect(result["data"]).to be_nil
      expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
    end
    expect(Favourite.count).to eq(1)
  end

  it "accepted_and_no_content_responses_have_distinct_results" do
    sign_in
    gate(:accepted)
    result = favourite
    expect(result["status"]).to eq("accepted")
    expect(result["httpStatus"]).to eq(202)
    expect(result["data"]).to eq({ "queued" => true })
    gate(:no_content)
    result = favourite
    expect(result["status"]).to eq("completed")
    expect(result["httpStatus"]).to eq(204)
    expect(result["data"]).to be_nil
    expect(result["error"]).to be_nil
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
    expect(Favourite.count).to eq(1)
  end

  it "http_failure_matrix_returns_safe_json_and_no_second_request" do
    sign_in
    [401, 403, 404, 409, 422, 429, 500, 503].each do |status|
      gate(status)
      result = favourite
      expect(result["status"]).to eq("failed")
      expect(result["httpStatus"]).to eq(status)
      expect(result["error"]["code"]).to eq("http_error")
      expect(result["data"]).to eq({ "errors" => { "fixture" => ["unavailable"] } })
      expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
    end
    # Even HTTP failure is not a rollback claim: this transport probe runs after commit.
    expect(Favourite.count).to eq(1)
  end

  it "browser_replay_keeps_one_fetch_and_application_deduplication" do
    sign_in
    # Count both callback and fetch entry without changing the packaged executor.
    measured = native(<<~JS)
      (await import('active_webmcp')).dispose();
      await document.modelContext.getTools();
      const { createRuntime, WebMCPAdapter } = await import('active_webmcp/runtime');
      const adapter = new WebMCPAdapter(document);
      const register = adapter.register.bind(adapter);
      window.disconnectCounts = { callbacks: 0, fetches: 0 };
      adapter.register = (definition, execute) => register(definition, (...args) => {
        window.disconnectCounts.callbacks++;
        return execute(...args);
      });
      window.measuredRuntime = createRuntime({ document, location, adapter, fetch: (...args) => {
        window.disconnectCounts.fetches++;
        return window.fetch(...args);
      }});
      await window.measuredRuntime.refresh();
      return true;
    JS
    expect(measured.fetch("ok")).to(be_truthy, measured.inspect)
    disconnected = gate(:disconnect)
    envelope = favourite
    disconnected.wait_for_commit
    counts = page.evaluate_script("window.disconnectCounts")
    puts "DISCONNECT_EVIDENCE=#{ { callbacks: counts['callbacks'], fetches: counts['fetches'], http_requests: ResponseGate.requests,
                                   rows: Favourite.count, result_status: envelope['status'] }.to_json}"
    expect(counts).to eq({ "callbacks" => 1, "fetches" => 1 })
    # Ben approved a gem-level no-retry guarantee, not at-most-once HTTP delivery.
    # Keep this pinned-browser replay observation separate from callback/fetch counts.
    expect(ResponseGate.requests).to eq([["POST", "/favourites"], ["POST", "/favourites"]])
    expect(envelope).to eq({ "status" => "completed", "httpStatus" => 200,
                             "data" => { "hotel_id" => 1, "saved" => true }, "error" => nil })
    expect(Favourite.count).to eq(1)
  end

  it "disconnection_during_response_body_does_not_claim_a_write_completed" do
    sign_in
    disconnected = gate(:disconnect_body)
    envelope = favourite
    disconnected.wait_for_commit
    expect(envelope["status"]).to eq("unknown")
    expect(envelope["error"]["code"]).to eq("request_failed")
    expect(envelope["data"]).to be_nil
    expect(Favourite.count).to eq(1)
    expect(ResponseGate.requests).to eq([["POST", "/favourites"]])
  end
end
