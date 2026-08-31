import { test } from "node:test";
import assert from "node:assert/strict";
import { createRuntime, WebMCPAdapter } from "../../app/assets/javascripts/active_webmcp/runtime.js";

const definition = () => ({ name: "search_hotels", description: "Search fixture hotels",
  inputSchema: { type: "object", properties: { destination: { type: "string" },
    count: { type: "integer" }, price: { type: "number" }, available: { type: "boolean" },
    category: { type: "string", enum: ["hotel", "hostel"] } }, required: ["destination"], additionalProperties: false },
  endpoint: { path: "/hotels/search", method: "GET" } });

function fixture({ definitions = [definition()], fetch = async () => Response.json({ hotels: [] }),
  adapter, timeoutMs = 30000 } = {}) {
  const state = { blocks: [{ textContent: JSON.stringify(definitions) }], tools: new Map(), requests: [], warnings: [], disposed: [], csrf: "fixture-token" };
  state.adapter = adapter || {
    available: () => true,
    async register(tool, execute) {
      if (state.tools.has(tool.name)) throw new Error("native collision with private details");
      state.tools.set(tool.name, execute);
      return () => { state.disposed.push(tool.name); state.tools.delete(tool.name); };
    }
  };
  state.runtime = createRuntime({ document: { querySelectorAll: () => state.blocks,
    querySelector: () => state.csrf === null ? null : { getAttribute: () => state.csrf } },
    location: new URL("https://example.test/gem"), adapter: state.adapter, timeoutMs,
    fetch: async (...args) => { state.requests.push(args); return fetch(...args); },
    logger: { warn: message => state.warnings.push(message) } });
  state.invoke = (input, options) => state.tools.get(definitions[0].name)(input, options);
  state.set = definitions => { state.blocks = [{ textContent: JSON.stringify(definitions) }]; };
  return state;
}

test("GET encodes flat values once and preserves endpoint JSON", async () => {
  const state = fixture({ fetch: async () => Response.json({ hotels: [{ name: "Fixture" }] }) });
  await state.runtime.refresh();
  const data = await state.invoke({ destination: "Sydney & 海滩?", count: 2, price: 3.5, available: false, category: "hotel" });
  assert.deepEqual(data, { status: "completed", httpStatus: 200, data: { hotels: [{ name: "Fixture" }] }, error: null });
  assert.equal(state.requests.length, 1);
  const [url, options] = state.requests[0];
  assert.equal(new URL(url).searchParams.get("destination"), "Sydney & 海滩?");
  assert.equal(new URL(url).searchParams.get("available"), "false");
  assert.equal(new URL(url).searchParams.get("count"), "2");
  assert.equal(new URL(url).origin, "https://example.test");
  assert.equal(options.method, "GET");
  assert.equal(options.credentials, "same-origin");
  assert.equal(options.redirect, "manual");
  assert.deepEqual(options.headers, { Accept: "application/json" });
  assert.equal(options.body, undefined);
});

test("invalid inputs never dispatch and error text contains no input values", async () => {
  const state = fixture();
  await state.runtime.refresh();
  for (const args of [null, [], {}, { destination: 42 }, { destination: "secret", url: "https://evil.test" },
    { destination: "secret", count: "2" }, { destination: "secret", count: 2**53 },
    { destination: "secret", price: Infinity }, { destination: "secret", available: "true" },
    { destination: "secret", category: "villa" }, { destination: { city: "secret" } }]) {
    const result = await state.invoke(args);
    assert.equal(result.status, "failed");
    assert.equal(result.httpStatus, null);
    assert.equal(result.data, null);
    assert.ok(result.error.code);
    assert.equal(result.error.message.includes("secret"), false);
  }
  assert.equal(state.requests.length, 0);
});

test("safe GET failures, status boundaries and no automatic retries", async () => {
  for (const [response, code] of [
    ...[401, 403, 404, 409, 422, 429, 500, 503].map(status => [() => Response.json({ secret: "private" }, { status }), "http_error"]),
    [() => new Response("<html>private</html>", { headers: { "Content-Type": "text/html" } }), "non_json_response"],
    [() => new Response("not json private", { headers: { "Content-Type": "application/json" } }), "invalid_json"],
    [() => { throw new TypeError("private fetch details"); }, "request_failed"],
    [() => ({ ok: true, redirected: true }), "redirect_blocked"]
  ]) {
    const state = fixture({ fetch: async () => response() });
    await state.runtime.refresh();
    const result = await state.invoke({ destination: "Sydney" });
    assert.equal(result.status, "failed");
    assert.equal(result.error.code, code);
    assert.equal(result.error.message.includes("private"), false);
    assert.equal(state.requests.length, 1);
    assert.deepEqual(state.warnings, []);
  }
  for (const data of [null, false, 7, ["a"], { hotels: [] }]) {
    const state = fixture({ fetch: async () => new Response(JSON.stringify(data), { headers: { "Content-Type": "application/vnd.fixture+json; charset=utf-8" } }) });
    await state.runtime.refresh();
    assert.deepEqual(await state.invoke({ destination: "Sydney" }), { status: "completed", httpStatus: 200, data, error: null });
  }
  const empty = fixture({ fetch: async () => new Response(null, { status: 204 }) });
  await empty.runtime.refresh();
  assert.deepEqual(await empty.invoke({ destination: "Sydney" }), { status: "completed", httpStatus: 204, data: null, error: null });
  const accepted = fixture({ fetch: async () => Response.json({ queued: true }, { status: 202 }) });
  await accepted.runtime.refresh();
  assert.deepEqual(await accepted.invoke({ destination: "Sydney" }), { status: "accepted", httpStatus: 202, data: { queued: true }, error: null });
});

test("timeout and callback cancellation abort one dispatched request", async () => {
  const waitingFetch = (_url, { signal }) => new Promise((_resolve, reject) => {
    signal.addEventListener("abort", () => reject(new DOMException("private", "AbortError")), { once: true });
  });
  const state = fixture({ fetch: waitingFetch, timeoutMs: 10 });
  await state.runtime.refresh();
  assert.equal((await state.invoke({ destination: "Sydney" })).error.code, "timeout");
  assert.equal(state.requests.length, 1);
  const cancelled = fixture({ fetch: waitingFetch });
  await cancelled.runtime.refresh();
  const abort = new AbortController();
  const pending = cancelled.invoke({ destination: "Sydney" }, { signal: abort.signal });
  abort.abort();
  assert.equal((await pending).error.code, "cancelled");
  assert.equal(cancelled.requests.length, 1);
  assert.equal((await cancelled.invoke({ destination: "Sydney" }, { signal: abort.signal })).error.code, "cancelled");
  assert.equal(cancelled.requests.length, 1);
});

test("refresh and multiple identical helper blocks have a single registration", async () => {
  const state = fixture();
  state.blocks.push({ textContent: JSON.stringify([definition()]) });
  await Promise.all([state.runtime.refresh(), state.runtime.refresh(), state.runtime.refresh()]);
  await state.runtime.refresh();
  assert.equal(state.tools.size, 1);
  assert.deepEqual(state.disposed, []);
  state.set([]);
  await state.runtime.refresh();
  assert.equal(state.tools.size, 0);
  assert.deepEqual(state.disposed, ["search_hotels"]);
  state.set([definition()]);
  await state.runtime.refresh();
  assert.equal(state.tools.size, 1);
  state.runtime.dispose();
  state.runtime.dispose();
  assert.equal(state.disposed.length, 2);
});

test("conflicting page metadata is diagnosed; unrelated registrations survive", async () => {
  const state = fixture();
  const unrelated = () => "foreign";
  state.tools.set("foreign", unrelated);
  await state.runtime.refresh();
  state.set([definition(), { ...definition(), description: "Conflicting" }]);
  await state.runtime.refresh();
  assert.deepEqual([...state.tools.keys()], ["foreign"]);
  assert.deepEqual(state.warnings, ["[ActiveWebMCP] invalid_page_manifest"]);
  assert.equal(state.tools.get("foreign"), unrelated);
});

test("native name collisions do not replace or unregister another owner", async () => {
  const state = fixture();
  const foreign = () => "original";
  state.tools.set("search_hotels", foreign);
  await state.runtime.refresh();
  assert.equal(state.tools.get("search_hotels"), foreign);
  assert.deepEqual(state.warnings, ["[ActiveWebMCP] registration_failed"]);
  state.runtime.dispose();
  assert.equal(state.tools.get("search_hotels"), foreign);
  assert.deepEqual(state.disposed, []);
});

test("manifest changes replace only the owned definition", async () => {
  const state = fixture();
  await state.runtime.refresh();
  state.set([{ ...definition(), description: "New description" }]);
  await state.runtime.refresh();
  assert.deepEqual(state.disposed, ["search_hotels"]);
  assert.equal(state.tools.size, 1);
});

test("cleanup during in-flight execution does not cancel or retry GET", async () => {
  let finish;
  const state = fixture({ fetch: () => new Promise(resolve => { finish = resolve; }) });
  await state.runtime.refresh();
  const pending = state.invoke({ destination: "Sydney" });
  state.runtime.dispose();
  assert.equal(state.tools.size, 0);
  assert.equal(state.requests[0][1].signal.aborted, false);
  finish(Response.json({ hotels: [] }));
  assert.deepEqual((await pending).data, { hotels: [] });
  assert.equal(state.requests.length, 1);
});

test("late registration after disposal is immediately cleaned up", async () => {
  let complete;
  let disposed = 0;
  const state = fixture({ adapter: { available: () => true,
    register: () => new Promise(resolve => { complete = () => resolve(() => disposed++); }) } });
  const refreshing = state.runtime.refresh();
  await Promise.resolve();
  state.runtime.dispose();
  complete();
  await refreshing;
  assert.equal(disposed, 1);
});

test("unsupported API and bad manifests disable enhancement safely", async () => {
  assert.equal(new WebMCPAdapter({}).available(), false);
  assert.equal(new WebMCPAdapter({ modelContext: { registerTool() {} } }).available(), false);
  const unsupported = fixture({ adapter: { available: () => false } });
  await unsupported.runtime.refresh();
  assert.deepEqual(unsupported.warnings, []);
  const invalid = [null, {}, { ...definition(), endpoint: { method: "DELETE", path: "/favourites" } },
    { ...definition(), title: " " }, { ...definition(), title: 7 },
    { ...definition(), annotations: null }, { ...definition(), annotations: [] },
    { ...definition(), annotations: { readOnlyHint: "true" } },
    { ...definition(), annotations: { destructiveHint: true } },
    ...["//evil.test/x", "https://evil.test/x", "/\\evil.test/x", "/hotels?destination=secret", "/x#fragment"].map(path => ({ ...definition(), endpoint: { method: "GET", path } })),
    { ...definition(), inputSchema: { ...definition().inputSchema, properties: { url: { type: "string" } }, required: [] } },
    { ...definition(), inputSchema: { ...definition().inputSchema, properties: { destination: { type: "string", enum: null } } } }];
  for (const value of invalid) {
    const state = fixture({ definitions: [value] });
    await state.runtime.refresh();
    assert.equal(state.tools.size, 0);
    assert.deepEqual(state.warnings, ["[ActiveWebMCP] invalid_page_manifest"]);
  }
  const malformed = fixture();
  malformed.blocks = [{ textContent: "not JSON secret" }];
  await malformed.runtime.refresh();
  assert.deepEqual(malformed.warnings, ["[ActiveWebMCP] invalid_page_manifest"]);
});

test("native adapter uses a separate registration lifetime", async () => {
  let options;
  let tool;
  const adapter = new WebMCPAdapter({ modelContext: { getTools() {}, async registerTool(t, o) { tool = t; options = o; } } });
  const execute = () => "result";
  const metadata = { ...definition(), title: "Search hotels",
    annotations: { readOnlyHint: true, untrustedContentHint: false } };
  const dispose = await adapter.register(metadata, execute);
  assert.equal(tool.execute, execute);
  assert.equal(tool.endpoint, undefined);
  assert.equal(tool.title, "Search hotels");
  assert.deepEqual(tool.annotations, { readOnlyHint: true, untrustedContentHint: false });
  assert.equal(options.signal.aborted, false);
  dispose();
  assert.equal(options.signal.aborted, true);
});

const writeDefinition = () => ({ name: "add_favourite", description: "Save a synthetic favourite",
  endpoint: { path: "/favourites", method: "POST" },
  inputSchema: { type: "object", properties: { hotel_id: { type: "integer" } }, required: ["hotel_id"], additionalProperties: false } });
const writeFixture = options => fixture({ definitions: [writeDefinition()], ...options });

test("POST serializes a typed JSON object with current CSRF and one request", async () => {
  const state = writeFixture({ fetch: async () => Response.json({ saved: true }, { status: 201 }) });
  await state.runtime.refresh();
  state.csrf = "replacement-fixture-token";
  const result = await state.invoke({ hotel_id: 1 });
  assert.deepEqual(result, { status: "completed", httpStatus: 201, data: { saved: true }, error: null });
  assert.equal(state.requests.length, 1);
  const [url, options] = state.requests[0];
  assert.equal(url, "https://example.test/favourites");
  assert.equal(options.method, "POST");
  assert.equal(options.credentials, "same-origin");
  assert.equal(options.redirect, "manual");
  assert.deepEqual(JSON.parse(options.body), { hotel_id: 1 });
  assert.deepEqual(options.headers, { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": "replacement-fixture-token" });
  assert.deepEqual(state.warnings, []);
});

test("missing CSRF, invalid header and invalid input prevent POST dispatch", async () => {
  for (const token of [null, "", " ", "bad\ntoken"]) {
    const state = writeFixture();
    await state.runtime.refresh();
    state.csrf = token;
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, "failed");
    assert.equal(result.httpStatus, null);
    assert.equal(result.data, null);
    assert.equal(result.error.code, token === "bad\ntoken" ? "invalid_csrf" : "missing_csrf");
    assert.equal(state.requests.length, 0);
  }
  const state = writeFixture();
  await state.runtime.refresh();
  for (const args of [{}, { hotel_id: "1" }, { hotel_id: 1, method: "DELETE" }, { hotel_id: 1, url: "https://evil.test" }]) {
    assert.equal((await state.invoke(args)).status, "failed");
  }
  assert.equal(state.requests.length, 0);
});

test("non-success HTTP results preserve application JSON without echoing it as error text", async () => {
  for (const status of [401, 403, 404, 409, 422, 429, 500, 503]) {
    const data = { errors: { hotel_id: ["safe validation detail"] } };
    const state = writeFixture({ fetch: async () => Response.json(data, { status }) });
    await state.runtime.refresh();
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, "failed");
    assert.equal(result.httpStatus, status);
    assert.deepEqual(result.data, data);
    assert.equal(result.error.code, "http_error");
    assert.equal(result.error.message.includes("validation detail"), false);
    assert.equal(state.requests.length, 1);
    assert.deepEqual(state.warnings, []);
  }
});

test("202 acknowledges acceptance, 204 completes without parsing, neither triggers another request", async () => {
  for (const [status, data, expected] of [[202, { queued: true }, "accepted"], [204, null, "completed"]]) {
    const state = writeFixture({ fetch: async () => status === 204 ? new Response(null, { status }) : Response.json(data, { status }) });
    await state.runtime.refresh();
    assert.deepEqual(await state.invoke({ hotel_id: 1 }), { status: expected, httpStatus: status, data, error: null });
    assert.equal(state.requests.length, 1);
  }
});

test("opaque redirects are never followed; writes have unknown outcome", async () => {
  for (const definition of [writeDefinition(), definitionForGet()]) {
    const state = fixture({ definitions: [definition], fetch: async () => ({ type: "opaqueredirect", status: 0 }) });
    await state.runtime.refresh();
    const result = await state.invoke(definition.endpoint.method === "POST" ? { hotel_id: 1 } : { destination: "Sydney" });
    assert.equal(result.status, definition.endpoint.method === "POST" ? "unknown" : "failed");
    assert.equal(result.httpStatus, null);
    assert.equal(result.error.code, "redirect_blocked");
    assert.equal(state.requests.length, 1);
    assert.equal(state.requests[0][1].redirect, "manual");
  }
});
function definitionForGet() { return definition(); }

test("HTML and malformed success JSON do not claim a write completed", async () => {
  for (const [response, code] of [
    [() => new Response("private HTML", { headers: { "Content-Type": "text/html" } }), "non_json_response"],
    [() => new Response("private malformed", { headers: { "Content-Type": "application/json" } }), "invalid_json"]
  ]) {
    const state = writeFixture({ fetch: async () => response() });
    await state.runtime.refresh();
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, "unknown");
    assert.equal(result.httpStatus, 200);
    assert.equal(result.data, null);
    assert.equal(result.error.code, code);
    assert.equal(result.error.message.includes("private"), false);
    assert.equal(state.requests.length, 1);
  }
});

test("POST transport failure or timeout is unknown after dispatch and never retried", async () => {
  for (const [fetch, code] of [
    [async () => { throw new TypeError("private network details"); }, "request_failed"],
    [() => new Promise(() => {}), "timeout"]
  ]) {
    const state = writeFixture({ fetch, timeoutMs: 5 });
    await state.runtime.refresh();
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, "unknown");
    assert.equal(result.httpStatus, null);
    assert.equal(result.error.code, code);
    assert.match(result.error.message, /do not automatically retry/);
    assert.equal(state.requests.length, 1);
  }
});

test("POST cancellation distinguishes before and after dispatch", async () => {
  const state = writeFixture({ fetch: () => new Promise(() => {}) });
  await state.runtime.refresh();
  const caller = new AbortController();
  const pending = state.invoke({ hotel_id: 1 }, { signal: caller.signal });
  caller.abort();
  const interrupted = await pending;
  assert.equal(interrupted.status, "unknown");
  assert.equal(interrupted.error.code, "cancelled");
  assert.equal(state.requests[0][1].signal.aborted, true);
  const before = await state.invoke({ hotel_id: 1 }, { signal: caller.signal });
  assert.equal(before.status, "failed");
  assert.equal(before.httpStatus, null);
  assert.equal(before.error.code, "cancelled");
  assert.equal(state.requests.length, 1);
});

test("timeout covers the body and retains known HTTP status evidence", async () => {
  for (const [status, expected] of [[200, "unknown"], [202, "accepted"], [422, "failed"], [500, "failed"]]) {
    const state = writeFixture({ timeoutMs: 5, fetch: async () => ({ status, ok: status < 300,
      headers: new Headers({ "Content-Type": "application/json" }), json: () => new Promise(() => {}) }) });
    await state.runtime.refresh();
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, expected);
    assert.equal(result.httpStatus, status);
    assert.equal(result.data, null);
    assert.equal(result.error.code, "timeout");
    assert.equal(state.requests.length, 1);
  }
});

test("known failed HTTP and 202 remain evidence even when the body is invalid", async () => {
  for (const [status, expected] of [[202, "accepted"], [422, "failed"], [500, "failed"]]) {
    const state = writeFixture({ fetch: async () => new Response("private HTML", { status, headers: { "Content-Type": "text/html" } }) });
    await state.runtime.refresh();
    const result = await state.invoke({ hotel_id: 1 });
    assert.equal(result.status, expected);
    assert.equal(result.error.code, "non_json_response");
    assert.equal(result.data, null);
    assert.equal(result.httpStatus, status);
  }
});

test("registration cleanup neither cancels nor resends a dispatched write", async () => {
  let finish;
  const state = writeFixture({ fetch: () => new Promise(resolve => { finish = resolve; }) });
  await state.runtime.refresh();
  const pending = state.invoke({ hotel_id: 1 });
  state.runtime.dispose();
  assert.equal(state.tools.size, 0);
  assert.equal(state.requests[0][1].signal.aborted, false);
  finish(Response.json({ saved: true }));
  assert.equal((await pending).status, "completed");
  assert.equal(state.requests.length, 1);
});

test("configured timeout bounds are validated and page metadata overrides the default", async () => {
  for (const timeoutMs of [0, -1, 1.5, "30", null, Infinity, 2147483648]) {
    assert.throws(() => writeFixture({ timeoutMs }), TypeError);
    const state = writeFixture({ definitions: [{ ...writeDefinition(), timeoutMs }] });
    await state.runtime.refresh();
    assert.equal(state.tools.size, 0);
    assert.deepEqual(state.warnings, ["[ActiveWebMCP] invalid_page_manifest"]);
  }
  const state = writeFixture({ definitions: [{ ...writeDefinition(), timeoutMs: 5 }], fetch: () => new Promise(() => {}) });
  await state.runtime.refresh();
  assert.equal((await state.invoke({ hotel_id: 1 })).error.code, "timeout");
});

test("queued refresh after disposal drops a late registration and owns only the newest page", async () => {
  const registrations = new Map();
  const disposed = [];
  let complete, entered;
  const waiting = new Promise(resolve => { entered = resolve; });
  const state = fixture({ adapter: { available: () => true,
    async register(tool) {
      if (tool.name === "search_hotels") await new Promise(resolve => { complete = resolve; entered(); });
      registrations.set(tool.name, tool);
      return () => { disposed.push(tool.name); registrations.delete(tool.name); };
    }
  } });
  const old = state.runtime.refresh();
  await waiting;
  state.runtime.dispose();
  state.set([writeDefinition()]);
  const current = state.runtime.refresh();
  complete();
  await Promise.all([old, current]);
  assert.deepEqual(disposed, ["search_hotels"]);
  assert.deepEqual([...registrations.keys()], ["add_favourite"]);
});

test("rejected registration recovers on next refresh and diagnostics contain codes only", async () => {
  let reject = true;
  const state = fixture({ adapter: { available: () => true, async register() {
    if (reject) throw new Error("fixture-token private-input private-body private-stack");
    return () => {};
  } } });
  await state.runtime.refresh();
  reject = false;
  await state.runtime.refresh();
  state.blocks = [{ textContent: "fixture-token private-input private-body private-stack" }];
  await state.runtime.refresh();
  assert.deepEqual(state.warnings, ["[ActiveWebMCP] registration_failed", "[ActiveWebMCP] invalid_page_manifest"]);
  assert.equal(state.requests.length, 0);
});

test("separate documents never share selections, CSRF or registration cleanup", async () => {
  const alice = writeFixture(), bob = writeFixture();
  alice.csrf = "alice-fixture-token";
  bob.csrf = "bob-fixture-token";
  await Promise.all([alice.runtime.refresh(), bob.runtime.refresh()]);
  await Promise.all([alice.invoke({ hotel_id: 1 }), bob.invoke({ hotel_id: 2 })]);
  assert.equal(alice.requests[0][1].headers["X-CSRF-Token"], "alice-fixture-token");
  assert.equal(bob.requests[0][1].headers["X-CSRF-Token"], "bob-fixture-token");
  alice.runtime.dispose();
  assert.equal(alice.tools.size, 0);
  assert.equal(bob.tools.size, 1);
  assert.deepEqual(bob.disposed, []);
});
