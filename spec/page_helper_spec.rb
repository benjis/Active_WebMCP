# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PageHelperTest" do
  before do
    Rails.application.reload_routes!
  end

  def helper_for(klass = HotelsController)
    # The helper has no request registry; each view supplies its current controller.
    controller = klass.new
    controller.set_request!(ActionDispatch::TestRequest.create)
    controller.view_context
  end

  def manifest(html)
    JSON.parse(Nokogiri::HTML.fragment(html).at_css("script[data-active-webmcp]").text)
  end

  it "local_lookup_by_public_name_and_request_time_route" do
    data = manifest(helper_for.webmcp_tools("search_hotels"))
    expect(data.map { |tool| tool["name"] }).to eq(["search_hotels"])
    expect(data[0]["endpoint"]).to eq({ "path" => "/hotels/search", "method" => "GET" })
    expect(data[0]["inputSchema"]["required"]).to eq(["destination"])
    expect { helper_for.webmcp_tools("search") }.to raise_error(ActiveWebMCP::ConfigurationError)
  end

  it "renders_optional_title_and_annotations_using_the_draft_field_names" do
    original = HotelsController.webmcp_definitions
    HotelsController.webmcp_tool :search, name: "metadata_probe", title: "Search hotels",
                                          description: "Search synthetic hotels", route: :search_hotels, method: :get,
                                          read_only_hint: true, untrusted_content_hint: false
    tool = manifest(helper_for.webmcp_tools("metadata_probe")).first

    expect(tool["title"]).to eq("Search hotels")
    expect(tool["annotations"]).to eq({ "readOnlyHint" => true, "untrustedContentHint" => false })
    expect(manifest(helper_for.webmcp_tools("escaped_metadata")).first).not_to include("title", "annotations")
  ensure
    HotelsController.webmcp_definitions = original
  end

  it "cross_controller_lookup_is_explicit" do
    view = helper_for(CatalogueController)
    expect { view.webmcp_tools("search_hotels") }.to raise_error(ActiveWebMCP::ConfigurationError)
    expect(manifest(view.webmcp_tools("search_hotels", controller: HotelsController))[0]["name"]).to eq("search_hotels")
    expect { view.webmcp_tools("search_hotels", controller: "HotelsController") }.to raise_error(ActiveWebMCP::ConfigurationError)
    expect(manifest(view.webmcp_tools)).to eq([])
    expect(manifest(helper_for.webmcp_tools("search_hotels", "search_hotels")).size).to eq(1)
  end

  it "inert_metadata_cannot_close_its_script_element" do
    original = HotelsController.webmcp_definitions
    HotelsController.webmcp_tool :search, name: "escape_probe", description: "</script><script>alert('x')</script>&\u2028",
                                          route: :search_hotels, method: :get
    html = helper_for.webmcp_tools("escape_probe")
    fragment = Nokogiri::HTML.fragment(html)
    expect(fragment.css("script").size).to eq(1)
    expect(fragment.at_css("script")["type"]).to eq("application/json")
    expect(manifest(html)[0]["description"]).to eq("</script><script>alert('x')</script>&\u2028")
    expect(html).not_to include("<script>alert")
  ensure
    HotelsController.webmcp_definitions = original
  end

  it "route_mismatches_dynamic_segments_and_missing_actions_fail" do
    original = HotelsController.webmcp_definitions
    invalid_routes = {
      missing: nil, wrong_controller: ["/bad", { to: "catalogue#index" }],
      wrong_action: ["/bad", { to: "hotels#index" }],
      dynamic: ["/bad/:id", { to: "hotels#search" }],
      optional_dynamic: ["/bad(/:id)", { to: "hotels#search" }],
      wildcard: ["/bad/*rest", { to: "hotels#search" }],
      wrong_method: ["/bad", { to: "hotels#search", via: :post }]
    }
    invalid_routes.each do |name, config|
      Rails.application.routes.draw do
        match config[0], **config[1], via: config[1].fetch(:via, :get), as: name if config
      end
      HotelsController.webmcp_definitions = {}.freeze
      HotelsController.webmcp_tool :search, name: "probe", description: "Probe", route: name, method: :get
      expect { helper_for.webmcp_tools("probe") }.to(raise_error(ActiveWebMCP::ConfigurationError), name.to_s)
    end
    Rails.application.routes.draw do
      get "/bad", to: "hotels#nonexistent", as: :missing_action
    end
    HotelsController.webmcp_definitions = {}.freeze
    HotelsController.webmcp_tool :nonexistent, name: "probe", description: "Probe", route: :missing_action, method: :get
    expect { helper_for.webmcp_tools("probe") }.to raise_error(ActiveWebMCP::ConfigurationError)
  ensure
    HotelsController.webmcp_definitions = original
    Rails.application.reload_routes!
  end

  it "shadowed_named_route_is_rejected" do
    Rails.application.routes.draw do
      get "/hotels/search", to: "catalogue#index"
      get "/hotels/search", to: "hotels#search", as: :search_hotels
    end
    expect { helper_for.webmcp_tools("search_hotels") }.to raise_error(ActiveWebMCP::ConfigurationError)
  ensure
    Rails.application.reload_routes!
  end

  it "url_is_resolved_at_render_time_not_retained_in_definition" do
    definition = HotelsController.webmcp_definitions.fetch("search_hotels")
    expect(manifest(helper_for.webmcp_tools("search_hotels"))[0]["endpoint"]["path"]).to eq("/hotels/search")
    Rails.application.routes.draw do
      get "/search/v2", to: "hotels#search", as: :search_hotels
    end
    expect(HotelsController.webmcp_definitions.fetch("search_hotels")).to equal(definition)
    expect(manifest(helper_for.webmcp_tools("search_hotels"))[0]["endpoint"]["path"]).to eq("/search/v2")
  ensure
    Rails.application.reload_routes!
  end

  it "timeout_configuration_is_validated_and_rendered" do
    config = Rails.application.config.active_webmcp
    original = config.timeout_ms
    config.timeout_ms = 1250
    expect(manifest(helper_for.webmcp_tools("search_hotels"))[0]["timeoutMs"]).to eq(1250)
    [nil, 0, -1, 1.5, "30000", 2_147_483_648].each do |invalid|
      config.timeout_ms = invalid
      expect { helper_for.webmcp_tools("search_hotels") }.to raise_error(ActiveWebMCP::ConfigurationError)
    end
  ensure
    config.timeout_ms = original
  end
end
