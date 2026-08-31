// Internal implementation. Only native WebMCP access lives in this adapter.
export class WebMCPAdapter {
  constructor(document) { this.document = document; }

  available() {
    const context = this.document.modelContext;
    return typeof context?.registerTool === "function" && typeof context?.getTools === "function";
  }

  async register(definition, execute) {
    const lifetime = new AbortController();
    const tool = { name: definition.name, description: definition.description,
      inputSchema: definition.inputSchema, execute };
    if (own(definition, "title")) tool.title = definition.title;
    if (own(definition, "annotations")) tool.annotations = definition.annotations;
    try {
      await this.document.modelContext.registerTool(tool, { signal: lifetime.signal });
    } catch (error) {
      lifetime.abort();
      throw error;
    }
    // This lifetime is NOT the execution callback's signal.
    return () => lifetime.abort();
  }
}

class ExecutionError extends Error {
  constructor(code) {
    super(`ActiveWebMCP: ${code}`);
    this.name = "ActiveWebMCPError";
    this.code = code;
  }
}

const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const scalar = (type, value) => {
  switch (type) {
    case "string": return typeof value === "string";
    case "boolean": return typeof value === "boolean";
    case "integer": return Number.isSafeInteger(value);
    case "number": return typeof value === "number" && Number.isFinite(value);
    default: return false;
  }
};
const reserved = new Set(["controller", "action", "format", "host", "protocol", "port", "url", "origin", "path",
  "method", "script_name", "authenticity_token", "_method", "utf8", "__proto__", "prototype", "constructor"]);

function validateInput(schema, input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new ExecutionError("invalid_input");
  for (const name of schema.required) {
    if (!own(input, name)) throw new ExecutionError("missing_parameter");
  }
  for (const [name, value] of Object.entries(input)) {
    if (!own(schema.properties, name)) throw new ExecutionError("unknown_parameter");
    const property = schema.properties[name];
    if (!scalar(property.type, value)) throw new ExecutionError("invalid_parameter_type");
    if (property.enum && !property.enum.includes(value)) throw new ExecutionError("invalid_parameter_enum");
  }
}

function validateDefinition(definition, location) {
  if (!definition || typeof definition.name !== "string" || !/^[a-zA-Z0-9_.-]{1,128}$/.test(definition.name) ||
      typeof definition.description !== "string" || !definition.description.trim()) throw new ExecutionError("invalid_manifest");
  if (own(definition, "title") && (typeof definition.title !== "string" || !definition.title.trim())) {
    throw new ExecutionError("invalid_manifest");
  }
  validateAnnotations(definition);
  const endpoint = definition.endpoint;
  if (!["GET", "POST"].includes(endpoint?.method) || typeof endpoint.path !== "string" || !/^\/(?!\/)/.test(endpoint.path) ||
      /[\\?#\x00-\x20]/.test(endpoint.path)) throw new ExecutionError("invalid_endpoint");
  const url = new URL(endpoint.path, location.href);
  if (url.origin !== location.origin) throw new ExecutionError("cross_origin_endpoint");
  if (own(definition, "timeoutMs") && !validTimeout(definition.timeoutMs)) throw new ExecutionError("invalid_timeout");
  const schema = definition.inputSchema;
  if (schema?.type !== "object" || schema.additionalProperties !== false || !schema.properties ||
      typeof schema.properties !== "object" || Array.isArray(schema.properties) || !Array.isArray(schema.required)) {
    throw new ExecutionError("invalid_schema");
  }
  for (const name of schema.required) {
    if (typeof name !== "string" || !own(schema.properties, name)) throw new ExecutionError("invalid_schema");
  }
  for (const [name, property] of Object.entries(schema.properties)) {
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name) || reserved.has(name) || !property ||
        !["string", "number", "integer", "boolean"].includes(property.type)) throw new ExecutionError("invalid_schema");
    if (own(property, "enum") && (!Array.isArray(property.enum) || !property.enum.length ||
        !property.enum.every(value => scalar(property.type, value)))) throw new ExecutionError("invalid_schema");
  }
}

function validateAnnotations(definition) {
  if (!own(definition, "annotations")) return;
  const annotations = definition.annotations;
  if (!annotations || typeof annotations !== "object" || Array.isArray(annotations)) {
    throw new ExecutionError("invalid_manifest");
  }
  const supported = new Set(["readOnlyHint", "untrustedContentHint"]);
  for (const [name, value] of Object.entries(annotations)) {
    if (!supported.has(name) || typeof value !== "boolean") throw new ExecutionError("invalid_manifest");
  }
}

const validTimeout = value => Number.isInteger(value) && value > 0 && value <= 2147483647;
const messages = Object.freeze({
  invalid_input: "Input must be a flat object.",
  missing_parameter: "A required parameter is missing.",
  unknown_parameter: "An unknown parameter was supplied.",
  invalid_parameter_type: "A parameter has an invalid type.",
  invalid_parameter_enum: "A parameter is outside its allowed values.",
  missing_csrf: "A current Rails CSRF token is required before sending this write.",
  invalid_csrf: "The Rails CSRF token cannot be used as a request header.",
  http_error: "The server returned an unsuccessful HTTP status.",
  redirect_blocked: "Redirects are not followed in JSON execution mode.",
  non_json_response: "The server did not return a JSON response.",
  invalid_json: "The server returned malformed JSON.",
  timeout: "The request exceeded its time limit.",
  cancelled: "The invocation was cancelled.",
  request_failed: "The request or response transfer could not be completed."
});
function result(status, httpStatus = null, data = null, code = null) {
  return { status, httpStatus, data, error: code ? { code,
    message: (messages[code] || messages.request_failed) +
      (status === "unknown" ? " The write outcome is unknown; do not automatically retry." : "") } : null };
}

// HTTP evidence is separate from business outcome. Never infer rollback from an
// interrupted write, and never change the application's JSON representation.
async function execute(definition, input, signal, { document, fetch, location, timeoutMs }) {
  const request = new AbortController();
  let dispatched = false;
  let httpStatus = null;
  let timeout;
  let cancel;
  let interruption;
  const isWrite = definition.endpoint.method === "POST";
  const incompleteStatus = () => {
    if (httpStatus === 202) return "accepted";
    if (httpStatus !== null && (httpStatus < 200 || httpStatus >= 300)) return "failed";
    return isWrite && dispatched ? "unknown" : "failed";
  };
  try {
    validateInput(definition.inputSchema, input);
    if (signal?.aborted) throw new ExecutionError("cancelled");
    const url = new URL(definition.endpoint.path, location.href);
    const options = { method: definition.endpoint.method, credentials: "same-origin", redirect: "manual",
      headers: { Accept: "application/json" }, signal: request.signal };
    if (isWrite) {
      // Read at invocation time, not when the page tools were registered.
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content");
      if (typeof token !== "string" || !token.trim()) throw new ExecutionError("missing_csrf");
      if (/[^\x20-\x7e]/.test(token)) throw new ExecutionError("invalid_csrf");
      options.headers["X-CSRF-Token"] = token;
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(Object.fromEntries(Object.entries(input)));
    } else {
      for (const [name, value] of Object.entries(input)) url.searchParams.set(name, String(value));
    }
    const interrupted = new Promise((_resolve, reject) => {
      const abort = code => {
        interruption ||= code;
        request.abort();
        reject(new ExecutionError(interruption));
      };
      cancel = () => abort("cancelled");
      signal?.addEventListener("abort", cancel, { once: true });
      timeout = setTimeout(() => abort("timeout"), definition.timeoutMs ?? timeoutMs);
    });
    const transfer = async () => {
      dispatched = true;
      // Exactly one fetch per dispatch. Browsers/transports can still replay a
      // POST internally; duplicate business effects must be prevented by the app.
      const response = await fetch(url.href, options);
      if (Number.isInteger(response.status) && response.status >= 100 && response.status <= 599) httpStatus = response.status;
      // Chrome exposes blocked redirects as opaque responses (no visible status).
      if (response.type === "opaqueredirect" || response.redirected ||
          (response.status >= 300 && response.status < 400)) throw new ExecutionError("redirect_blocked");
      if (httpStatus === null) throw new ExecutionError("request_failed");
      if (request.signal.aborted) throw new ExecutionError(interruption);
      if (httpStatus === 204) return result("completed", httpStatus);
      const mediaType = (response.headers.get("Content-Type") || "").split(";", 1)[0].trim().toLowerCase();
      if (mediaType !== "application/json" && !/^application\/[a-z0-9.+-]+\+json$/.test(mediaType)) {
        throw new ExecutionError("non_json_response");
      }
      let data;
      try { data = await response.json(); }
      catch (error) {
        if (request.signal.aborted) throw new ExecutionError(interruption);
        throw new ExecutionError(error instanceof SyntaxError ? "invalid_json" : "request_failed");
      }
      if (request.signal.aborted) throw new ExecutionError(interruption);
      if (!response.ok) return result("failed", httpStatus, data, "http_error");
      return result(httpStatus === 202 ? "accepted" : "completed", httpStatus, data);
    };
    // Includes body transfer, not merely receipt of the HTTP response headers.
    return await Promise.race([transfer(), interrupted]);
  } catch (error) {
    const code = interruption || (error instanceof ExecutionError ? error.code : "request_failed");
    return result(incompleteStatus(), httpStatus, null, code);
  } finally {
    clearTimeout(timeout);
    if (cancel) signal?.removeEventListener("abort", cancel);
  }
}

export function createRuntime({ document, location, fetch, adapter = new WebMCPAdapter(document),
  logger = console, timeoutMs = 30000 }) {
  if (!validTimeout(timeoutMs)) throw new TypeError("timeoutMs must be an integer from 1 to 2147483647");
  const owned = new Map();
  let generation = 0;
  let queue = Promise.resolve();
  const warn = code => logger.warn(`[ActiveWebMCP] ${code}`);
  const release = () => {
    for (const tool of owned.values()) tool.dispose();
    owned.clear();
  };
  const dispose = () => { generation++; release(); };

  function refresh() {
    const revision = ++generation;
    queue = queue.then(async () => {
      if (revision !== generation) return;
      let selected;
      try {
        if (!adapter.available()) { release(); return; }
        selected = new Map();
        for (const block of document.querySelectorAll('script[type="application/json"][data-active-webmcp]')) {
          const definitions = JSON.parse(block.textContent);
          if (!Array.isArray(definitions)) throw new ExecutionError("invalid_manifest");
          for (const definition of definitions) {
            validateDefinition(definition, location);
            const fingerprint = JSON.stringify(definition);
            if (selected.has(definition.name) && selected.get(definition.name).fingerprint !== fingerprint) {
              throw new ExecutionError("conflicting_page_tools");
            }
            selected.set(definition.name, { definition, fingerprint });
          }
        }
      } catch {
        release(); warn("invalid_page_manifest"); return;
      }
      for (const [name, tool] of owned) {
        if (selected.get(name)?.fingerprint !== tool.fingerprint) {
          tool.dispose(); owned.delete(name);
        }
      }
      for (const [name, { definition, fingerprint }] of selected) {
        if (revision !== generation) return;
        if (owned.has(name)) continue;
        try {
          const cleanup = await adapter.register(definition, (input, { signal } = {}) =>
            execute(definition, input, signal, { document, fetch, location, timeoutMs }));
          if (revision !== generation) { cleanup(); return; }
          owned.set(name, { fingerprint, dispose: cleanup });
        } catch {
          // registerTool rejects a collision; never remove or adopt the other owner.
          warn("registration_failed");
        }
      }
    });
    return queue;
  }
  return { refresh, dispose };
}
