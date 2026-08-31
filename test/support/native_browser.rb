# frozen_string_literal: true

require "capybara/rspec"
require "selenium-webdriver"
require_relative "response_gate"
require_relative "stale_document_reads"
Capybara::Selenium::ChromeNode.prepend(StaleDocumentReads)

module NativeBrowserSupport
  ROOT = File.expand_path("../..", __dir__)
  BROWSER = File.join(ROOT,
                      "tmp/browser/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing")
  DRIVER = File.join(ROOT, "tmp/browser/chromedriver-mac-arm64/chromedriver")
  VERSION = "153.0.8010.12"
  unless File.executable?(BROWSER) && File.executable?(DRIVER)
    raise "Run ruby bin/setup-browser first; native tests must not silently skip"
  end

  Capybara.app = ResponseGate.new(Rails.application)
  Capybara.server = :puma, { Silent: true }
  Capybara.server_host = "127.0.0.1"
  Capybara.default_max_wait_time = 10
  Capybara.register_driver :native_webmcp do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.binary = BROWSER
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
    options.add_argument("--enable-experimental-web-platform-features")
    options.add_argument("--enable-features=WebMCPTesting")
    options.add_argument("--no-first-run")
    options.add_argument("--no-default-browser-check")
    service = Selenium::WebDriver::Service.chrome(path: DRIVER)
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
  end
  Capybara.default_driver = :native_webmcp

  Capybara.register_driver :ordinary_chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.binary = BROWSER
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
    options.add_argument("--disable-blink-features=WebMCP,WebMCPTesting")
    options.add_argument("--no-first-run")
    options.add_argument("--no-default-browser-check")
    service = Selenium::WebDriver::Service.chrome(path: DRIVER)
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
  end

  def native(source)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      (async () => { #{source} })().then(
        value => done({ ok: true, value }),
        error => done({ ok: false, name: error.name, message: error.message })
      );
    JS
  end

  def invoke(name, args = {})
    native(<<~JS)
      const tools = await document.modelContext.getTools();
      const tool = tools.find(t => t.name === #{name.to_json});
      return await document.modelContext.executeTool(tool, #{args.to_json.to_json});
    JS
  end
end
