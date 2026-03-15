defmodule McpServer.IconTest do
  use ExUnit.Case, async: true

  alias McpServer.Icon

  doctest McpServer.Icon

  describe "Icon.new/1" do
    test "creates icon struct with required src field" do
      icon = Icon.new(src: "https://example.com/icon.png")

      assert %Icon{} = icon
      assert icon.src == "https://example.com/icon.png"
      assert icon.mime_type == nil
      assert icon.sizes == []
    end

    test "creates icon with all fields" do
      icon =
        Icon.new(
          src: "https://example.com/icon.png",
          mime_type: "image/png",
          sizes: ["48x48", "96x96"]
        )

      assert icon.src == "https://example.com/icon.png"
      assert icon.mime_type == "image/png"
      assert icon.sizes == ["48x48", "96x96"]
    end

    test "raises when src is missing" do
      assert_raise KeyError, fn ->
        Icon.new(mime_type: "image/png")
      end
    end

    test "raises when src is not a string" do
      assert_raise ArgumentError, "src must be a string", fn ->
        Icon.new(src: 123)
      end
    end

    test "raises when mime_type is not a string or nil" do
      assert_raise ArgumentError, "mime_type must be a string or nil", fn ->
        Icon.new(src: "https://example.com/icon.png", mime_type: 123)
      end
    end

    test "raises when sizes is not a list" do
      assert_raise ArgumentError, "sizes must be a list", fn ->
        Icon.new(src: "https://example.com/icon.png", sizes: "48x48")
      end
    end
  end

  describe "JSON encoding" do
    test "encodes icon with all fields" do
      icon =
        Icon.new(
          src: "https://example.com/icon.png",
          mime_type: "image/png",
          sizes: ["48x48", "96x96"]
        )

      json = Jason.encode!(icon)
      decoded = Jason.decode!(json)

      assert decoded["src"] == "https://example.com/icon.png"
      assert decoded["mimeType"] == "image/png"
      assert decoded["sizes"] == ["48x48", "96x96"]
    end

    test "omits mimeType when nil" do
      icon = Icon.new(src: "https://example.com/icon.png")
      json = Jason.encode!(icon)
      decoded = Jason.decode!(json)

      assert decoded["src"] == "https://example.com/icon.png"
      refute Map.has_key?(decoded, "mimeType")
    end

    test "omits sizes when empty" do
      icon = Icon.new(src: "https://example.com/icon.png")
      json = Jason.encode!(icon)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "sizes")
    end

    test "encodes list of icons as array" do
      icons = [
        Icon.new(
          src: "https://example.com/icon-48.png",
          mime_type: "image/png",
          sizes: ["48x48"]
        ),
        Icon.new(src: "https://example.com/icon-96.png", mime_type: "image/png", sizes: ["96x96"])
      ]

      json = Jason.encode!(icons)
      decoded = Jason.decode!(json)

      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["src"] == "https://example.com/icon-48.png"
      assert Enum.at(decoded, 1)["src"] == "https://example.com/icon-96.png"
    end
  end
end
