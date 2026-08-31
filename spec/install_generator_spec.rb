# frozen_string_literal: true

require "rails_helper"
require "generators/active_webmcp/install/install_generator"
require "tmpdir"
require "fileutils"

RSpec.describe "InstallGeneratorTest" do
  before do
    @destination = Dir.mktmpdir("active-webmcp-generator-")
    write("config/importmap.rb", "pin \"application\"\n")
    write("app/javascript/application.js", "// Keep the app's own imports\nimport \"@hotwired/turbo-rails\"\n")
    write("app/views/layouts/application.html.erb", "<%= javascript_importmap_tags %>\n")
  end

  after do
    # Only the exact temporary test directory created above is removed.
    FileUtils.remove_entry(@destination)
  end

  def write(path, content)
    target = File.join(@destination, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end

  def read(path)
    File.read(File.join(@destination, path))
  end

  def install
    capture(:stdout) do
      ActiveWebMCP::Generators::InstallGenerator.new([], {}, destination_root: @destination).invoke_all
    end
  end

  it "install_is_idempotent_and_preserves_application_code" do
    expect(ActiveWebMCP::Generators::InstallGenerator.namespace).to eq("active_webmcp:install")
    install
    first = [read("config/importmap.rb"), read("app/javascript/application.js")]
    install
    expect([read("config/importmap.rb"), read("app/javascript/application.js")]).to eq(first)
    expect(first[0]).to include('pin "active_webmcp/runtime", to: "active_webmcp/runtime.js"')
    expect(first[1]).to include('import "active_webmcp";')
    expect(first[1]).to include('import "@hotwired/turbo-rails"')
    expect(first[1].scan('import "active_webmcp"').size).to eq(1)
  end

  it "recognizes_existing_single_quoted_setup" do
    write("config/importmap.rb",
          "pin 'active_webmcp', to: 'active_webmcp.js'\npin 'active_webmcp/runtime', to: 'active_webmcp/runtime.js'\n")
    write("app/javascript/application.js", "import 'active_webmcp' // Keep this\n")
    before = [read("config/importmap.rb"), read("app/javascript/application.js")]
    install
    expect([read("config/importmap.rb"), read("app/javascript/application.js")]).to eq(before)
  end

  it "conflict_fails_before_writing_either_file" do
    write("config/importmap.rb", "pin 'active_webmcp/runtime', to: 'custom.js'\n")
    before = [read("config/importmap.rb"), read("app/javascript/application.js")]
    expect { install }.to raise_error(Rails::Generators::Error)
    expect([read("config/importmap.rb"), read("app/javascript/application.js")]).to eq(before)
  end

  it "missing_importmap_layout_fails_before_writing" do
    write("app/views/layouts/application.html.erb", "<%= javascript_include_tag 'application' %>\n")
    expect { install }.to raise_error(Rails::Generators::Error)
    expect(read("app/javascript/application.js")).not_to include('import "active_webmcp"')
  end

  it "nonstandard_pins_are_not_silently_overwritten" do
    ["pin('active_webmcp', to: 'custom.js')\n", "pin(\n  'active_webmcp',\n  to: 'custom.js'\n)\n"].each do |source|
      write("config/importmap.rb", source)
      expect { install }.to raise_error(Rails::Generators::Error)
      expect(read("config/importmap.rb")).to eq(source)
      expect(read("app/javascript/application.js")).not_to include('import "active_webmcp"')
    end
  end
end
