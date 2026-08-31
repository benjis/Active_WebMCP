# Changelog

## 0.1.0 — 2026-09-01

- Explicit controller declarations and page-selected public tool names; local and
  explicit cross-controller lookup, immutable schemas and Rails reload support.
- Flat string/integer/number/boolean parameters with descriptions, required fields
  and enums; strict validation, no coercion or agent-controlled routing.
- Named same-origin GET/POST JSON execution with Rails sessions and current CSRF.
- `{ status, httpStatus, data, error }` results, 202/204 handling, blocked redirects,
  safe error codes, transfer-wide configurable timeout and unknown write outcomes.
- Native WebMCP adapter, document ownership, Turbo Drive/cache restoration,
  cleanup independent of execution cancellation, and unsupported-browser fallback.
- Optional human-readable tool titles plus read-only and untrusted-content
  annotations from the current WebMCP draft.
- Idempotent Rails 8.1 importmap/Propshaft installer; nonce CSP and production
  precompiled assets verified on the pinned setup.
- Search/favourite examples and request, Node and pinned native-browser checks.
- Local gem-package installation verification with isolated gem home and fresh
  Rails app; no package publication is performed by verification scripts.

### Changes during development

The first development implementation returned raw endpoint JSON to a native caller. This release instead
wraps it under `data`; the Rails HTTP response format is unchanged.

### Known limits

Pinned experimental Chrome only; no polyfill, separate MCP server, UI updates,
navigation execution, forms, dynamic paths, nested inputs, Frames/Streams,
framework adapters or API-only/cross-origin integration. Browser replay requires
application deduplication. MIT licensed.
