defmodule McpServer.Tool.MetaTest do
  use ExUnit.Case, async: true

  alias McpServer.Tool.Meta
  alias McpServer.Tool.Meta.UI

  describe "new/1" do
    test "creates struct with defaults" do
      meta = Meta.new()
      assert meta.ui == nil
    end

    test "creates struct with UI value" do
      ui = UI.new(resource_uri: "ui://test/dashboard")
      meta = Meta.new(ui: ui)
      assert meta.ui == ui
    end
  end

  describe "Jason.Encoder" do
    test "encodes empty meta as empty object" do
      meta = Meta.new()
      assert Jason.encode!(meta) == "{}"
    end

    test "encodes meta with UI value" do
      ui = UI.new(resource_uri: "ui://test/dashboard")
      meta = Meta.new(ui: ui)
      json = Jason.decode!(Jason.encode!(meta))

      assert json["ui"]["resourceUri"] == "ui://test/dashboard"
    end

    test "omits nil fields" do
      meta = Meta.new()
      json = Jason.decode!(Jason.encode!(meta))
      refute Map.has_key?(json, "ui")
    end
  end
end
