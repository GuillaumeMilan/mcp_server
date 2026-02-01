defmodule McpServer.Resource.Meta.UITest do
  use ExUnit.Case, async: true

  alias McpServer.Resource.Meta.UI
  alias McpServer.Resource.Meta.UI.CSP
  alias McpServer.Resource.Meta.UI.Permissions

  describe "new/1" do
    test "creates struct with defaults" do
      meta = UI.new()
      assert meta.csp == nil
      assert meta.permissions == nil
      assert meta.domain == nil
      assert meta.prefers_border == nil
    end

    test "creates struct with all options" do
      meta =
        UI.new(
          csp:
            CSP.new(connect_domains: ["api.example.com"], resource_domains: ["cdn.example.com"]),
          permissions: Permissions.new(camera: true, microphone: true),
          domain: "a904794854a047f6.example.com",
          prefers_border: true
        )

      assert meta.csp.connect_domains == ["api.example.com"]
      assert meta.csp.resource_domains == ["cdn.example.com"]
      assert meta.permissions.camera == true
      assert meta.permissions.microphone == true
      assert meta.domain == "a904794854a047f6.example.com"
      assert meta.prefers_border == true
    end
  end

  describe "Jason.Encoder" do
    test "encodes empty meta as empty object" do
      meta = UI.new()
      assert Jason.encode!(meta) == "{}"
    end

    test "encodes CSP with camelCase keys" do
      meta =
        UI.new(
          csp:
            CSP.new(
              connect_domains: ["api.example.com"],
              resource_domains: ["cdn.example.com"],
              frame_domains: ["frame.example.com"],
              base_uri_domains: ["base.example.com"]
            )
        )

      json = Jason.decode!(Jason.encode!(meta))

      assert json["csp"]["connectDomains"] == ["api.example.com"]
      assert json["csp"]["resourceDomains"] == ["cdn.example.com"]
      assert json["csp"]["frameDomains"] == ["frame.example.com"]
      assert json["csp"]["baseUriDomains"] == ["base.example.com"]
    end

    test "encodes permissions with camelCase keys and empty map values" do
      meta = UI.new(permissions: Permissions.new(camera: true, clipboard_write: true))
      json = Jason.decode!(Jason.encode!(meta))

      assert json["permissions"]["camera"] == %{}
      assert json["permissions"]["clipboardWrite"] == %{}
    end

    test "encodes prefersBorder" do
      meta = UI.new(prefers_border: true)
      json = Jason.decode!(Jason.encode!(meta))
      assert json["prefersBorder"] == true
    end

    test "encodes domain" do
      meta = UI.new(domain: "example.com")
      json = Jason.decode!(Jason.encode!(meta))
      assert json["domain"] == "example.com"
    end

    test "omits nil fields" do
      meta = UI.new(domain: "example.com")
      json = Jason.decode!(Jason.encode!(meta))

      refute Map.has_key?(json, "csp")
      refute Map.has_key?(json, "permissions")
      refute Map.has_key?(json, "prefersBorder")
      assert Map.has_key?(json, "domain")
    end

    test "CSP omits empty domain lists" do
      meta = UI.new(csp: CSP.new(connect_domains: ["api.example.com"]))
      json = Jason.decode!(Jason.encode!(meta))

      assert json["csp"]["connectDomains"] == ["api.example.com"]
      refute Map.has_key?(json["csp"], "resourceDomains")
      refute Map.has_key?(json["csp"], "frameDomains")
      refute Map.has_key?(json["csp"], "baseUriDomains")
    end

    test "Permissions omits false values" do
      meta = UI.new(permissions: Permissions.new(camera: true))
      json = Jason.decode!(Jason.encode!(meta))

      assert json["permissions"]["camera"] == %{}
      refute Map.has_key?(json["permissions"], "microphone")
      refute Map.has_key?(json["permissions"], "geolocation")
      refute Map.has_key?(json["permissions"], "clipboardWrite")
    end
  end
end
