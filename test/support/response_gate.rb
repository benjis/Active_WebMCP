# frozen_string_literal: true

require "timeout"

# Native-test-only transport fault injection around the REAL Rails endpoint.
# Nothing is added to controller parameters, public routes or packaged gem code.
class ResponseGate
  class Gate
    attr_reader :mode

    def initialize(mode)
      @mode = mode
      @entered = Queue.new
      @released = Queue.new
    end

    def entered!
      @entered << true
    end

    def wait_for_commit
      Timeout.timeout(10) { @entered.pop }
    end

    def wait_for_release
      Timeout.timeout(10) { @released.pop }
    end

    def release
      @released << true
    end
  end

  @mutex = Mutex.new
  @requests = []
  class << self
    def arm(mode, method: "POST", path: "/favourites")
      @mutex.synchronize do
        @pending = [method, path, Gate.new(mode)]
        @requests = []
        @pending.last
      end
    end

    def take(method, path)
      @mutex.synchronize do
        @requests << [method, path] unless path.start_with?("/assets/")
        if @pending && @pending.first(2) == [method, path]
          gate = @pending.last
          @pending = nil
          gate
        end
      end
    end

    def requests
      @mutex.synchronize { @requests.dup }
    end

    def reset
      @mutex.synchronize do
        @pending = nil
        @requests = []
      end
    end
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    gate = self.class.take(env["REQUEST_METHOD"], env["PATH_INFO"])
    response = @app.call(env)
    return response unless gate

    # Rails has finished its transaction before any delay/response replacement.
    gate.entered!
    status, _, body = response
    case gate.mode
    when :disconnect, :disconnect_body
      body.close if body.respond_to?(:close)
      # Full Rack hijack hands this one test connection to us. Close it after
      # commit. A truncated body is distinguishable from closure before headers,
      # which this Chrome build may transparently retry within a single fetch.
      connection = env.fetch("rack.hijack").call
      if gate.mode == :disconnect_body
        connection.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 128\r\nConnection: close\r\n\r\n{\"saved\":")
      end
      connection.close
      [-1, {}, []]
    when :hold
      gate.wait_for_release
      response
    when :hold_body
      body.close if body.respond_to?(:close)
      stream = Enumerator.new do |output|
        output << '{"saved":'
        gate.wait_for_release
        output << "true}"
      end
      [status, { "content-type" => "application/json" }, stream]
    else
      body.close if body.respond_to?(:close)
      case gate.mode
      when :redirect then [303, { "location" => "/navigation_target", "content-type" => "text/html" }, ["Redirect"]]
      when :html then [200, { "content-type" => "text/html" }, ["<html>Fixture response</html>"]]
      when :invalid_json then [200, { "content-type" => "application/json" }, ["not JSON"]]
      when :accepted then [202, { "content-type" => "application/json" }, ['{"queued":true}']]
      when :no_content then [204, {}, []]
      when Integer then [gate.mode, { "content-type" => "application/json" },
                         ['{"errors":{"fixture":["unavailable"]}}']]
      else raise "Unknown response gate mode"
      end
    end
  end
end
