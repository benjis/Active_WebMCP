# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe "ReloadTest" do
  it "real_rails_reload_does_not_retain_controller_classes" do
    output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../test/support/reload_check.rb", __dir__))
    expect(status.success?).to(be_truthy, output)
    expect(output).to include("cross-controller selection rendered: PASS")
    expect(output).to include("removed declaration absent: PASS")
  end
end
