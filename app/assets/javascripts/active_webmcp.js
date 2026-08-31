import { createRuntime } from "active_webmcp/runtime";

// One owner per document, even if an entrypoint is initialized more than once.
const key = Symbol.for("active_webmcp.runtime");
if (!globalThis[key]) {
  const runtime = createRuntime({ document, location, fetch: globalThis.fetch.bind(globalThis) });
  globalThis[key] = runtime;
  document.addEventListener("DOMContentLoaded", () => runtime.refresh());
  window.addEventListener("pageshow", () => runtime.refresh());
  window.addEventListener("pagehide", () => runtime.dispose());
  // Turbo Drive replaces the body without replacing this document's runtime.
  // Keep previews inactive; reconcile on the completed visit (including cached
  // restoration). Frames, Streams and custom routers are not supported here.
  document.addEventListener("turbo:before-cache", () => runtime.dispose());
  document.addEventListener("turbo:before-render", () => runtime.dispose());
  document.addEventListener("turbo:load", () => runtime.refresh());
}
const runtime = globalThis[key];
export const refresh = () => runtime.refresh();
export const dispose = () => runtime.dispose();
refresh();
