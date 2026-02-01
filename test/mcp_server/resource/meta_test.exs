defmodule McpServer.Resource.MetaTest do
  use ExUnit.Case, async: true

  alias McpServer.Resource.Meta
  alias McpServer.Resource.Meta.UI

  describe "new/1" do
    test "creates struct with defaults" do
      meta = Meta.new()
      assert meta.ui == nil
    end

    test "creates struct with UI value" do
      ui = UI.new(domain: "example.com")
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
      ui = UI.new(domain: "example.com")
      meta = Meta.new(ui: ui)
      json = Jason.decode!(Jason.encode!(meta))

      assert json["ui"]["domain"] == "example.com"
    end

    test "omits nil fields" do
      meta = Meta.new()
      json = Jason.decode!(Jason.encode!(meta))
      refute Map.has_key?(json, "ui")
    end
  end
end
