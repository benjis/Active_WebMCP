# ActiveWebMCP

[![CI](https://github.com/benjis/Active_WebMCP/actions/workflows/ci.yml/badge.svg)](https://github.com/benjis/Active_WebMCP/actions/workflows/ci.yml)

Turn selected Rails controller actions into tools that browser-based AI agents
can discover and call.

ActiveWebMCP keeps your application in control. Your existing Rails actions still
handle authentication, authorization, validation, database writes, and JSON
responses. You do not need a separate MCP server or handwritten registration
JavaScript.

## Status and WebMCP support

`0.1.0` is the current release.

WebMCP does not currently have numbered protocol releases. ActiveWebMCP targets
the [W3C WebMCP Draft Community Group Report dated 26 August 2026](https://webmachinelearning.github.io/webmcp/),
at upstream revision
[`41d12f0`](https://github.com/webmachinelearning/webmcp/commit/41d12f057167ccf5954dbcf49d99502cb6c84491).
It supports the draft's imperative `document.modelContext` API:

- tool registration with `name`, `title`, `description`, `inputSchema`,
  `annotations`, and `execute`
- registration cleanup with `AbortSignal`
- execution cancellation with `AbortSignal`
- JSON-serializable tool results

This release is tested with Chrome for Testing `153.0.8010.12` on Apple
Silicon macOS. Chrome exposes WebMCP experimentally; it is not yet a stable,
widely available browser API. ActiveWebMCP does not currently support declarative
form tools or cross-origin tool exposure.

## Requirements

- Ruby 3.3 or newer
- Rails 8.1
- importmap-rails
- Propshaft
- a browser with the experimental WebMCP API

The tested Rails stack is Ruby `3.3.12`, Rails `8.1.3.1`, importmap-rails `2.2.3`,
and Propshaft `1.3.2`.

## Quick start

### 1. Add the gem

For development from a nearby checkout:

```ruby
# Gemfile
gem "active_webmcp", path: "../Active_WebMCP"
```

For the published `0.1.0` release:

```ruby
# Gemfile
gem "active_webmcp", "0.1.0"
```

Then install the JavaScript entrypoint and importmap pins:

```sh
bundle install
bin/rails generate active_webmcp:install
```

The generator is safe to run more than once. It stops without changing files if
it finds an importmap conflict or an unsupported layout.

### 2. Declare a read tool

Start with an existing controller action that returns JSON:

```ruby
class HotelsController < ApplicationController
  webmcp_tool :search,
    name: "search_hotels",
    title: "Search hotels",
    description: "Search hotels by destination. Does not book or pay.",
    read_only_hint: true,
    untrusted_content_hint: true,
    route: :search_hotels,
    method: :get,
    parameters: {
      destination: {
        type: :string,
        required: true,
        description: "City or region"
      }
    }

  def search
    hotels = Hotel.where(destination: params.require(:destination))
    render json: { hotels: hotels.as_json(only: %i[id name destination]) }
  end
end
```

Use a named route:

```ruby
# config/routes.rb
get "/hotels/search", to: "hotels#search", as: :search_hotels
```

### 3. Select the tool on a page

A declared tool is not exposed automatically. Select it in the view where it
should be available:

```erb
<%= webmcp_tools "search_hotels" %>
```

That is enough. ActiveWebMCP renders safe JSON metadata and registers the tool
when the page loads. If WebMCP is unavailable, the rest of the page continues to
work normally.

### Optional tool metadata

Use `title` as a short label that a browser or agent can show to a person. The
description can remain a fuller explanation of what the tool does.

Two optional annotations describe expected behaviour:

- `read_only_hint: true` says the tool should not change application state.
- `untrusted_content_hint: true` says the result may include content that should
  not be treated as trusted instructions.

These annotations are hints for clients. They do not enforce permissions,
sandbox content, or replace authentication, authorization, and input validation.

## Write tool example

POST tools use the same Rails session and CSRF protection as the rest of your app:

```ruby
class FavouritesController < ApplicationController
  before_action :authenticate_user!

  webmcp_tool :create,
    name: "add_favourite",
    title: "Add favourite",
    description: "Save a hotel to the current user's favourites. Does not book it.",
    route: :favourites,
    method: :post,
    parameters: {
      hotel_id: { type: :integer, required: true }
    }

  def create
    favourite = current_user.favourites.create_or_find_by!(
      hotel_id: params.require(:hotel_id)
    )

    render json: { hotel_id: favourite.hotel_id, saved: true }
  end
end
```

```ruby
# config/routes.rb
post "/favourites", to: "favourites#create", as: :favourites
```

Select a tool from another controller explicitly:

```erb
<%= webmcp_tools "add_favourite", controller: FavouritesController %>
```

ActiveWebMCP reads the current CSRF token when the agent invokes the tool. Rails
must still authenticate the user, authorize the record, and validate every input.
Use database constraints or another idempotency strategy for writes because a
browser or network intermediary may replay a POST.

## Supported parameters

ActiveWebMCP intentionally supports a small, predictable schema:

| Type | Ruby declaration | Example value |
| --- | --- | --- |
| String | `type: :string` | `"Sydney"` |
| Integer | `type: :integer` | `42` |
| Number | `type: :number` | `12.5` |
| Boolean | `type: :boolean` | `true` |

Each parameter can use `required`, `description`, and a type-matching `enum`.
Nested objects, arrays, default values, silent type conversion, and unknown input
fields are rejected.

## Tool results

The Rails action owns the JSON inside `data`. ActiveWebMCP wraps it in a small
result envelope:

```json
{
  "status": "completed",
  "httpStatus": 200,
  "data": {
    "hotels": [
      { "id": 1, "name": "Harbour Hotel", "destination": "Sydney" }
    ]
  },
  "error": null
}
```

`status` can be `completed`, `accepted`, `failed`, or `unknown`. An interrupted
write can be `unknown` because a timeout cannot prove whether the server committed
the change. ActiveWebMCP never retries a tool request automatically.

## Configuration

The default timeout is 30 seconds. Change it in an initializer:

```ruby
# config/initializers/active_webmcp.rb
Rails.application.config.active_webmcp.timeout_ms = 10_000
```

Keep these Rails helpers in your layout:

```erb
<%= csrf_meta_tags %>
<%= csp_meta_tag %>
<%= javascript_importmap_tags %>
```

The installer does not weaken your Content Security Policy.

## Important boundaries

- Only explicitly selected tools are visible on a page.
- Only named, same-origin GET and POST routes are supported.
- Dynamic path segments and wildcard routes are not supported.
- Authentication and authorization remain application responsibilities.
- Tool annotations are advisory metadata, not security controls.
- Tool descriptions and results may contain untrusted text.
- Turbo Drive navigation and page restoration are supported.
- Turbo Frames, Streams, morph navigation, and custom routers are not supported.
- Missing WebMCP support must not replace or break the human interface.

See [SECURITY.md](SECURITY.md) before exposing actions that read private data or
change application state.

## Development

Run the fast Ruby and JavaScript suites:

```sh
bundle exec ruby bin/test
npm test
bundle exec rubocop
```

The Ruby suite uses RSpec. The JavaScript suite uses Node's built-in test runner.

Native browser tests require the pinned Apple Silicon Chrome build:

```sh
ruby bin/setup-browser
bundle exec ruby bin/test --native
```

Release verification builds isolated Rails applications and a real gem artifact:

```sh
bundle exec ruby bin/check-clean-install
bundle exec ruby bin/check-production
bundle exec ruby bin/check-package
```

The demonstration Rails application lives in `test/dummy` and contains only
synthetic users and records. It is never included in the gem.

## License

ActiveWebMCP is available under the [MIT License](LICENSE). See
[CHANGELOG.md](CHANGELOG.md) for release changes.
