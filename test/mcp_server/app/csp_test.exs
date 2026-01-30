defmodule McpServer.App.CSPTest do
  use ExUnit.Case, async: true

  alias McpServer.App.CSP
  alias McpServer.App.UIResourceMeta

  describe "generate/1" do
    test "returns restrictive default for nil" do
      csp = CSP.generate(nil)
      assert csp =~ "default-src 'none'"
      assert csp =~ "script-src 'self' 'unsafe-inline'"
      assert csp =~ "style-src 'self' 'unsafe-inline'"
      assert csp =~ "img-src 'self' data:"
      assert csp =~ "media-src 'self' data:"
      assert csp =~ "connect-src 'none'"
    end

    test "returns restrictive default for meta without CSP" do
      meta = UIResourceMeta.new()
      csp = CSP.generate(meta)
      assert csp =~ "connect-src 'none'"
    end

    test "adds connect domains to connect-src" do
      meta = UIResourceMeta.new(csp: %{connect_domains: ["api.example.com", "ws.example.com"]})
      csp = CSP.generate(meta)

      assert csp =~ "connect-src 'self' api.example.com ws.example.com"
    end

    test "adds resource domains to script/style/img/media/font-src" do
      meta = UIResourceMeta.new(csp: %{resource_domains: ["cdn.example.com"]})
      csp = CSP.generate(meta)

      assert csp =~ "script-src 'self' 'unsafe-inline' cdn.example.com"
      assert csp =~ "style-src 'self' 'unsafe-inline' cdn.example.com"
      assert csp =~ "img-src 'self' data: cdn.example.com"
      assert csp =~ "media-src 'self' data: cdn.example.com"
      assert csp =~ "font-src 'self' cdn.example.com"
    end

    test "adds frame domains to frame-src" do
      meta = UIResourceMeta.new(csp: %{frame_domains: ["iframe.example.com"]})
      csp = CSP.generate(meta)

      assert csp =~ "frame-src iframe.example.com"
    end

    test "adds base-uri domains" do
      meta = UIResourceMeta.new(csp: %{base_uri_domains: ["base.example.com"]})
      csp = CSP.generate(meta)

      assert csp =~ "base-uri base.example.com"
    end

    test "omits frame-src when no frame domains" do
      meta = UIResourceMeta.new(csp: %{connect_domains: ["api.example.com"]})
      csp = CSP.generate(meta)

      refute csp =~ "frame-src"
    end

    test "omits base-uri when no base-uri domains" do
      meta = UIResourceMeta.new(csp: %{connect_domains: ["api.example.com"]})
      csp = CSP.generate(meta)

      refute csp =~ "base-uri"
    end

    test "combines multiple domain types" do
      meta =
        UIResourceMeta.new(
          csp: %{
            connect_domains: ["api.example.com"],
            resource_domains: ["cdn.example.com"],
            frame_domains: ["frame.example.com"],
            base_uri_domains: ["base.example.com"]
          }
        )

      csp = CSP.generate(meta)

      assert csp =~ "connect-src 'self' api.example.com"
      assert csp =~ "cdn.example.com"
      assert csp =~ "frame-src frame.example.com"
      assert csp =~ "base-uri base.example.com"
    end

    test "connect-src is 'none' when no connect domains" do
      meta = UIResourceMeta.new(csp: %{resource_domains: ["cdn.example.com"]})
      csp = CSP.generate(meta)

      assert csp =~ "connect-src 'none'"
    end
  end
end
