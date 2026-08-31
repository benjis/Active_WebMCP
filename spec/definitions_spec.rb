# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DefinitionsTest" do
  def declaration(**changes)
    { name: "search", description: "Search hotels", route: :search_hotels, method: :get,
      parameters: { destination: { type: :string, required: true } } }.merge(changes)
  end

  it "flat_schema_is_strict_and_immutable_without_freezing_caller_data" do
    parameters = { destination: { type: :string, required: true, description: "City", enum: [+"Sydney"] },
                   count: { type: :integer }, price: { type: :number }, available: { type: :boolean } }
    schema = ActiveWebMCP::SchemaCompiler.compile(parameters)
    expect(schema["required"]).to eq(["destination"])
    expect(schema["additionalProperties"]).to eq(false)
    expect(schema["properties"].values.map { |property| property["type"] }).to eq(%w[string integer number boolean])
    parameters[:destination][:enum][0].replace("Melbourne")
    expect(schema["properties"]["destination"]["enum"]).to eq(["Sydney"])
    expect { schema["properties"]["destination"]["enum"] << "Perth" }.to raise_error(FrozenError)
    type = String.new("string")
    ActiveWebMCP::SchemaCompiler.compile(x: { type: type })
    expect(type.frozen?).not_to be_truthy
  end

  it "rejects_unsupported_schemas_and_routing_inputs" do
    invalid = [nil, [], { x: :string }, { x: { type: :object } }, { x: { type: :array } },
               { x: { type: :string, required: "true" } }, { x: { type: :string, default: "a" } },
               { x: { type: :string, description: 5 } }, { x: { type: :integer, enum: [1.5] } },
               { x: { type: :integer, enum: [2**53] } }, { x: { type: :number, enum: [Float::INFINITY] } },
               { x: { type: :boolean, enum: ["true"] } }, { x: { type: :string, enum: [] } },
               { x: { type: :string, enum: nil } }, { x: { type: :string, "type" => :integer } },
               { x: { type: :string }, "x" => { type: :string } }, { "x[y]" => { type: :string } }]
    ActiveWebMCP::SchemaCompiler::RESERVED.each { |name| invalid << { name => { type: :string } } }
    invalid.each { |parameters| expect { ActiveWebMCP::SchemaCompiler.compile(parameters) }.to raise_error(ActiveWebMCP::ConfigurationError) }
  end

  it "declaration_rejects_unsupported_options_and_modes" do
    klass = Class.new(ActionController::Base)
    [{ method: :delete }, { execution: :navigate }, { description: " " }, { name: "not a name" },
     { route: "https://example.org" }, { title: " " }, { title: 5 }, { read_only_hint: nil },
     { untrusted_content_hint: "true" }, { timeout: 30 }].each do |changes|
      expect { klass.webmcp_tool(:search, **declaration(**changes)) }.to raise_error(ActiveWebMCP::ConfigurationError)
    end
    expect { klass.webmcp_tool(:search) }.to raise_error(ActiveWebMCP::ConfigurationError)
  end

  it "stores_optional_title_and_annotations_immutably" do
    klass = Class.new(ActionController::Base)
    title = +"Search hotels"
    klass.webmcp_tool(:search, **declaration(title: title, read_only_hint: true, untrusted_content_hint: true))
    definition = klass.webmcp_definitions.fetch("search")

    title.replace("Changed")
    expect(definition.title).to eq("Search hotels")
    expect(definition.annotations).to eq({ readOnlyHint: true, untrustedContentHint: true })
    expect(definition.annotations).to be_frozen

    defaults = ActiveWebMCP::ToolDefinition.new(:search, **declaration)
    expect(defaults.title).to be_nil
    expect(defaults.annotations).to be_nil
  end

  it "inheritance_is_copy_on_write_and_duplicate_names_fail" do
    parent = Class.new(ActionController::Base)
    parent.webmcp_tool(:search, **declaration)
    child = Class.new(parent)
    child.webmcp_tool(:search, **declaration(name: "child_search"))
    expect(parent.webmcp_definitions.keys).to eq(["search"])
    expect(child.webmcp_definitions.keys).to eq(%w[search child_search])
    expect(child.webmcp_definitions["search"]).to equal(parent.webmcp_definitions["search"])
    expect(parent.webmcp_definitions["search"].frozen?).to be_truthy
    expect { child.webmcp_tool(:search, **declaration) }.to raise_error(ActiveWebMCP::ConfigurationError)
  end

  it "post_is_an_explicit_supported_verb" do
    klass = Class.new(ActionController::Base)
    klass.webmcp_tool(:create, **declaration(name: "add_favourite", method: :post, route: :favourites))
    expect(klass.webmcp_definitions.fetch("add_favourite").method).to eq("POST")
  end
end
