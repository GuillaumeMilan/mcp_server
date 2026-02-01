defmodule McpServer.Tool.Meta.UITest do
  use ExUnit.Case, async: true

  alias McpServer.Tool.Meta.UI

  describe "new/1" do
    test "creates struct with defaults" do
      ui = UI.new()
      assert ui.resource_uri == nil
      assert ui.visibility == [:model, :app]
    end

    test "creates struct with all options" do
      ui = UI.new(resource_uri: "ui://weather/dashboard", visibility: [:app])
      assert ui.resource_uri == "ui://weather/dashboard"
      assert ui.visibility == [:app]
    end

    test "default visibility includes model and app" do
      ui = UI.new(resource_uri: "ui://test")
      assert ui.visibility == [:model, :app]
    end
  end

  describe "Jason.Encoder" do
    test "encodes with camelCase keys and string visibility" do
      ui = UI.new(resource_uri: "ui://test/view", visibility: [:model, :app])
      json = Jason.decode!(Jason.encode!(ui))

      assert json["resourceUri"] == "ui://test/view"
      assert json["visibility"] == ["model", "app"]
    end

    test "omits nil resourceUri" do
      ui = UI.new(visibility: [:app])
      json = Jason.decode!(Jason.encode!(ui))

      refute Map.has_key?(json, "resourceUri")
      assert json["visibility"] == ["app"]
    end

    test "always includes visibility" do
      ui = UI.new()
      json = Jason.decode!(Jason.encode!(ui))

      assert json["visibility"] == ["model", "app"]
    end
  end
end
