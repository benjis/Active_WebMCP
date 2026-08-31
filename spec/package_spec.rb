# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"
require "tmpdir"

RSpec.describe "PackageTest" do
  let(:root) { File.expand_path("..", __dir__) }

  it "package_contains_runtime_public_documents_and_approved_license_only" do
    spec = Gem::Specification.load(File.join(root, "active_webmcp.gemspec"))
    expect(spec.version.to_s).to eq("0.1.0")
    expect(spec.licenses).to eq(["MIT"])
    expect(spec.email).to eq(["zbin.song@gmail.com"])
    required = %w[LICENSE README.md SECURITY.md CHANGELOG.md
                  app/assets/javascripts/active_webmcp.js app/assets/javascripts/active_webmcp/runtime.js
                  lib/generators/active_webmcp/install/install_generator.rb]
    required.each { |path| expect(spec.files).to include(path) }
    expect(spec.files).to all(match(%r{\A(?:app/|lib/|LICENSE\z|README\.md\z|SECURITY\.md\z|CHANGELOG\.md\z)}))
    expect(spec.files).not_to include(a_string_matching(%r{(?:\A|/)(?:tmp|test|node_modules|\.internal_docs|\.DS_Store)(?:/|\z)}))
    spec.files.each do |path|
      expect(File.symlink?(File.join(root, path))).not_to(be_truthy,
                                                          "Do not follow a symlink into the package: #{path}")
      source = File.binread(File.join(root, path))
      expect(/AIza[0-9A-Za-z_-]{35}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.match?(source)).not_to(
        be_truthy, "Credential-like content in packaged file: #{path}"
      )
    end
    Dir.mktmpdir("active-webmcp-package-test-") do |directory|
      artifact = File.join(directory, "candidate.gem")
      capture(:stdout) { Dir.chdir(root) { Gem::Package.build(spec, false, false, artifact) } }
      package = Gem::Package.new(artifact)
      package.verify
      expect(package.contents.sort).to eq(spec.files.sort)
      expect(package.spec.licenses).to eq(["MIT"])
    end
  end

  it "public_document_links_resolve_inside_the_package" do
    spec = Gem::Specification.load(File.join(root, "active_webmcp.gemspec"))
    spec.files.grep(/\.md\z/).each do |path|
      File.read(File.join(root, path)).scan(/\[[^\]\n]+\]\(([^)\s]+)\)/).flatten.each do |target|
        next if target.match?(/\A(?:https?:|mailto:|#)/)

        resolved = File.expand_path(target.split("#").first, File.dirname(File.join(root, path)))
        relative = resolved.delete_prefix("#{root}/")
        expect(spec.files).to(include(relative), "Broken packaged link from #{path} to #{target}")
      end
    end
  end
end
