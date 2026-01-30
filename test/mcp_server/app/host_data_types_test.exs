defmodule McpServer.App.HostDataTypesTest do
  use ExUnit.Case, async: true

  alias McpServer.App.HostCapabilities
  alias McpServer.App.HostContext
  alias McpServer.App.AppCapabilities

  describe "HostCapabilities" do
    test "creates struct with defaults" do
      caps = HostCapabilities.new()
      assert caps.experimental == nil
      assert caps.open_links == nil
      assert caps.server_tools == nil
      assert caps.server_resources == nil
      assert caps.logging == nil
      assert caps.sandbox == nil
    end

    test "creates struct with all options" do
      caps =
        HostCapabilities.new(
          open_links: %{},
          server_tools: %{list_changed: true},
          server_resources: %{list_changed: false},
          logging: %{},
          sandbox: %{permissions: %{camera: %{}}}
        )

      assert caps.open_links == %{}
      assert caps.server_tools == %{list_changed: true}
      assert caps.server_resources == %{list_changed: false}
      assert caps.logging == %{}
      assert caps.sandbox == %{permissions: %{camera: %{}}}
    end

    test "encodes to JSON with camelCase keys" do
      caps =
        HostCapabilities.new(
          open_links: %{},
          server_tools: %{list_changed: true},
          logging: %{}
        )

      json = Jason.decode!(Jason.encode!(caps))

      assert json["openLinks"] == %{}
      assert json["serverTools"]["listChanged"] == true
      assert json["logging"] == %{}
    end

    test "omits nil fields from JSON" do
      caps = HostCapabilities.new(open_links: %{})
      json = Jason.decode!(Jason.encode!(caps))

      assert Map.has_key?(json, "openLinks")
      refute Map.has_key?(json, "serverTools")
      refute Map.has_key?(json, "logging")
      refute Map.has_key?(json, "experimental")
    end
  end

  describe "HostContext" do
    test "creates struct with defaults" do
      ctx = HostContext.new()
      assert ctx.theme == nil
      assert ctx.display_mode == nil
      assert ctx.locale == nil
    end

    test "creates struct with all options" do
      ctx =
        HostContext.new(
          theme: "dark",
          display_mode: "inline",
          available_display_modes: ["inline", "fullscreen"],
          locale: "en-US",
          time_zone: "America/New_York",
          platform: "desktop",
          device_capabilities: %{touch: false, hover: true},
          safe_area_insets: %{top: 0, right: 0, bottom: 0, left: 0}
        )

      assert ctx.theme == "dark"
      assert ctx.display_mode == "inline"
      assert ctx.available_display_modes == ["inline", "fullscreen"]
      assert ctx.locale == "en-US"
      assert ctx.time_zone == "America/New_York"
      assert ctx.platform == "desktop"
    end

    test "encodes to JSON with camelCase keys" do
      ctx =
        HostContext.new(
          theme: "dark",
          display_mode: "inline",
          available_display_modes: ["inline", "fullscreen"],
          locale: "en-US",
          time_zone: "America/New_York"
        )

      json = Jason.decode!(Jason.encode!(ctx))

      assert json["theme"] == "dark"
      assert json["displayMode"] == "inline"
      assert json["availableDisplayModes"] == ["inline", "fullscreen"]
      assert json["locale"] == "en-US"
      assert json["timeZone"] == "America/New_York"
    end

    test "omits nil fields from JSON" do
      ctx = HostContext.new(theme: "light")
      json = Jason.decode!(Jason.encode!(ctx))

      assert json["theme"] == "light"
      refute Map.has_key?(json, "displayMode")
      refute Map.has_key?(json, "locale")
    end
  end

  describe "AppCapabilities" do
    test "creates struct with defaults" do
      caps = AppCapabilities.new()
      assert caps.experimental == nil
      assert caps.tools == nil
      assert caps.available_display_modes == nil
    end

    test "creates struct with all options" do
      caps =
        AppCapabilities.new(
          tools: %{list_changed: true},
          available_display_modes: ["inline", "fullscreen"]
        )

      assert caps.tools == %{list_changed: true}
      assert caps.available_display_modes == ["inline", "fullscreen"]
    end

    test "encodes to JSON with camelCase keys" do
      caps =
        AppCapabilities.new(
          tools: %{list_changed: true},
          available_display_modes: ["inline"]
        )

      json = Jason.decode!(Jason.encode!(caps))

      assert json["tools"]["listChanged"] == true
      assert json["availableDisplayModes"] == ["inline"]
    end

    test "omits nil fields from JSON" do
      caps = AppCapabilities.new()
      json = Jason.decode!(Jason.encode!(caps))

      refute Map.has_key?(json, "tools")
      refute Map.has_key?(json, "experimental")
    end
  end
end
