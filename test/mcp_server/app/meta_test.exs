defmodule McpServer.App.MetaTest do
  use ExUnit.Case, async: true

  alias McpServer.App.Meta
  alias McpServer.App.UI
  alias McpServer.App.UIResourceMeta

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

    test "creates struct with UIResourceMeta value" do
      ui_meta = UIResourceMeta.new(domain: "example.com")
      meta = Meta.new(ui: ui_meta)
      assert meta.ui == ui_meta
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
