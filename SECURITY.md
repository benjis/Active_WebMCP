# Security guidance

ActiveWebMCP is an experimental browser enhancement, not an authorization layer.
Security reports should be submitted privately through
[GitHub Security Advisories](https://github.com/benjis/Active_WebMCP/security/advisories/new).
Do not put tokens, personal records, private responses or exploit details into a
public issue.

## Application responsibilities

- Authenticate every request, authorize the record and tenant, validate input and
  enforce transactions. Tool visibility and descriptions are not permission grants.
- Keep Rails CSRF protection enabled and render current `csrf_meta_tags`. The gem
  reads the token at invocation time; it cannot repair expired sessions or tokens.
- Use named GET routes only for reads and named POST routes for writes. Never put
  writes behind GET. Preserve authorization for human and agent callers alike.
- Return only JSON you intend the caller/agent to see, including error responses.
  The gem preserves application JSON under `data`; it does not redact it for you.
- Scope record queries and uniqueness constraints appropriately. The fixture's
  `create_or_find_by!` and unique index are an example, not general idempotency for
  arbitrary operations. Payments, refunds and irreversible actions are out of scope.
- Avoid shared caches for session-specific pages/CSRF metadata. Old browser snapshots
  are not proof of current authorization. Own cache invalidation on identity changes.
- Configure Rails/application/proxy log filtering. Gem diagnostics contain static
  codes; this does not control Rails request logs, browser logs or agent traces.

## Transport and outcomes

Each dispatched invocation makes one gem-level `fetch`. There is no automatic
retry, UI refresh request or rollback. A browser can transparently replay a POST
inside that fetch; design application-owned deduplication for duplicate delivery.

Timeout, cancellation or a lost/invalid successful POST response can leave the
outcome `unknown`. Do not blindly resubmit. A native caller's cancellation may
prevent delivery of any final envelope. A non-success HTTP status is not proof
that a transaction rolled back. HTTP 202 is accepted, not completed.

Requests use same-origin credentials, JSON Accept and manual redirects. Missing
CSRF prevents POST dispatch. Server-side CSRF and access checks remain mandatory.
Never supply routing decisions from agent inputs. The alpha rejects dynamic paths,
wildcards, cross-origin endpoints and reserved routing parameters.

## Browser, CSP and agent boundary

Only selected tool metadata is emitted, as escaped inert JSON. Executable code is
in packaged external modules; there is no eval or inline callback. Applications
own CSP. Rails importmap's inline bootstrap still needs an approved nonce/hash
policy; do not disable CSP just to make tools load.

Page text and tool results can contain prompt injection. This gem does not make
untrusted text safe instructions, constrain an agent's reasoning, or implement
confirmation for sensitive actions. A hostile same-origin script/extension is
outside this library's isolation guarantees.

Use pinned test browsers with isolated profiles. Inspector requests broad host
access and can retain its Gemini key: use fixture data only. Configure credentials
through Inspector's UI, never in source, CLI arguments, committed files or chat.
Keep profiles out of version control and rotate temporary test credentials.

## Reporting

Provide the gem/browser/Rails versions, affected boundary, sanitized reproduction
and whether a business write may have committed. Do not send real credentials or
tenant/customer data. Submitting a report does not create a guaranteed response
time or support commitment.
