defmodule McpServer.Tool.ContentTest do
  use ExUnit.Case, async: true

  alias McpServer.Tool.Content

  doctest McpServer.Tool.Content

  describe "Text.new/1" do
    test "creates text struct with required text field" do
      text = Content.Text.new(text: "Hello, World!")

      assert %Content.Text{} = text
      assert text.text == "Hello, World!"
    end

    test "raises when text field is missing" do
      assert_raise KeyError, fn ->
        Content.Text.new([])
      end
    end

    test "raises when text is not a string" do
      assert_raise ArgumentError, "text must be a string", fn ->
        Content.Text.new(text: 123)
      end
    end

    test "accepts empty string" do
      text = Content.Text.new(text: "")
      assert text.text == ""
    end

    test "accepts unicode text" do
      text = Content.Text.new(text: "Hello 世界 🌍")
      assert text.text == "Hello 世界 🌍"
    end
  end

  describe "Image.new/1" do
    test "creates image struct with required fields" do
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      image = Content.Image.new(data: image_data, mime_type: "image/png")

      assert %Content.Image{} = image
      assert image.data == image_data
      assert image.mime_type == "image/png"
    end

    test "raises when data field is missing" do
      assert_raise KeyError, fn ->
        Content.Image.new(mime_type: "image/png")
      end
    end

    test "raises when mime_type field is missing" do
      assert_raise KeyError, fn ->
        Content.Image.new(data: <<1, 2, 3>>)
      end
    end

    test "raises when data is not binary" do
      assert_raise ArgumentError, "data must be a binary", fn ->
        Content.Image.new(data: 123, mime_type: "image/png")
      end
    end

    test "raises when mime_type is not string" do
      assert_raise ArgumentError, "mime_type must be a string", fn ->
        Content.Image.new(data: <<1, 2, 3>>, mime_type: 123)
      end
    end

    test "accepts empty binary data" do
      image = Content.Image.new(data: <<>>, mime_type: "image/gif")
      assert image.data == <<>>
    end
  end

  describe "Resource.new/1" do
    test "creates resource struct with required uri field" do
      resource = Content.Resource.new(uri: "file:///path/to/file.txt")

      assert %Content.Resource{} = resource
      assert resource.uri == "file:///path/to/file.txt"
      assert resource.text == nil
      assert resource.blob == nil
      assert resource.mime_type == nil
    end

    test "creates resource with optional text field" do
      resource = Content.Resource.new(uri: "file:///data.json", text: "content")

      assert resource.uri == "file:///data.json"
      assert resource.text == "content"
      assert resource.blob == nil
      assert resource.mime_type == nil
    end

    test "creates resource with optional blob field" do
      blob = <<255, 216, 255>>
      resource = Content.Resource.new(uri: "file:///image.png", blob: blob)

      assert resource.uri == "file:///image.png"
      assert resource.blob == blob
      assert resource.text == nil
    end

    test "creates resource with optional mime_type field" do
      resource = Content.Resource.new(uri: "file:///data.json", mime_type: "application/json")

      assert resource.mime_type == "application/json"
    end

    test "creates resource with all fields" do
      blob = <<1, 2, 3>>

      resource =
        Content.Resource.new(
          uri: "file:///file.bin",
          text: "description",
          blob: blob,
          mime_type: "application/octet-stream"
        )

      assert resource.uri == "file:///file.bin"
      assert resource.text == "description"
      assert resource.blob == blob
      assert resource.mime_type == "application/octet-stream"
    end

    test "raises when uri field is missing" do
      assert_raise KeyError, fn ->
        Content.Resource.new(text: "content")
      end
    end

    test "raises when uri is not a string" do
      assert_raise ArgumentError, "uri must be a string", fn ->
        Content.Resource.new(uri: 123)
      end
    end

    test "raises when text is not a string or nil" do
      assert_raise ArgumentError, "text must be a string or nil", fn ->
        Content.Resource.new(uri: "file:///test", text: 123)
      end
    end

    test "raises when blob is not a binary or nil" do
      assert_raise ArgumentError, "blob must be a binary or nil", fn ->
        Content.Resource.new(uri: "file:///test", blob: 123)
      end
    end

    test "raises when mime_type is not a string or nil" do
      assert_raise ArgumentError, "mime_type must be a string or nil", fn ->
        Content.Resource.new(uri: "file:///test", mime_type: 123)
      end
    end
  end

  describe "JSON encoding for Text" do
    test "encodes text struct to correct JSON format" do
      text = Content.Text.new(text: "Hello, World!")
      json = Jason.encode!(text)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "text"
      assert decoded["text"] == "Hello, World!"
      assert map_size(decoded) == 2
    end

    test "handles special characters in text" do
      text = Content.Text.new(text: ~s({"key": "value"}))
      json = Jason.encode!(text)
      decoded = Jason.decode!(json)

      assert decoded["text"] == ~s({"key": "value"})
    end
  end

  describe "JSON encoding for Image" do
    test "encodes image struct with base64 data" do
      image_data = <<255, 216, 255>>
      image = Content.Image.new(data: image_data, mime_type: "image/jpeg")
      json = Jason.encode!(image)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "image"
      assert decoded["data"] == Base.encode64(image_data)
      assert decoded["mimeType"] == "image/jpeg"
      assert map_size(decoded) == 3
    end

    test "encodes empty binary as empty string" do
      image = Content.Image.new(data: <<>>, mime_type: "image/png")
      json = Jason.encode!(image)
      decoded = Jason.decode!(json)

      assert decoded["data"] == ""
    end

    test "properly encodes PNG header" do
      png_header = <<137, 80, 78, 71, 13, 10, 26, 10>>
      image = Content.Image.new(data: png_header, mime_type: "image/png")
      json = Jason.encode!(image)
      decoded = Jason.decode!(json)

      assert decoded["data"] == "iVBORw0KGgo="
    end
  end

  describe "JSON encoding for Resource" do
    test "encodes resource struct with URI only" do
      resource = Content.Resource.new(uri: "file:///path/to/file.txt")
      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "resource"
      assert decoded["resource"]["uri"] == "file:///path/to/file.txt"
      assert map_size(decoded["resource"]) == 1
    end

    test "encodes resource with text" do
      resource =
        Content.Resource.new(
          uri: "file:///data.json",
          text: ~s({"key": "value"}),
          mime_type: "application/json"
        )

      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["resource"]["uri"] == "file:///data.json"
      assert decoded["resource"]["text"] == ~s({"key": "value"})
      assert decoded["resource"]["mimeType"] == "application/json"
      refute Map.has_key?(decoded["resource"], "blob")
    end

    test "encodes resource with blob as base64" do
      blob = <<255, 216, 255>>

      resource =
        Content.Resource.new(
          uri: "file:///image.png",
          blob: blob,
          mime_type: "image/png"
        )

      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["resource"]["blob"] == Base.encode64(blob)
      assert decoded["resource"]["mimeType"] == "image/png"
      refute Map.has_key?(decoded["resource"], "text")
    end

    test "only includes non-nil fields in JSON" do
      resource = Content.Resource.new(uri: "file:///test.txt", mime_type: "text/plain")

      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["resource"]["uri"] == "file:///test.txt"
      assert decoded["resource"]["mimeType"] == "text/plain"
      refute Map.has_key?(decoded["resource"], "text")
      refute Map.has_key?(decoded["resource"], "blob")
    end
  end

  describe "MCP protocol compliance" do
    test "all content types have 'type' field in JSON" do
      text = Content.Text.new(text: "test")
      image = Content.Image.new(data: <<1, 2, 3>>, mime_type: "image/png")
      resource = Content.Resource.new(uri: "file:///test")

      text_json = Jason.decode!(Jason.encode!(text))
      image_json = Jason.decode!(Jason.encode!(image))
      resource_json = Jason.decode!(Jason.encode!(resource))

      assert text_json["type"] == "text"
      assert image_json["type"] == "image"
      assert resource_json["type"] == "resource"
    end

    test "content list can be encoded as array" do
      contents = [
        Content.Text.new(text: "First"),
        Content.Image.new(data: <<1, 2, 3>>, mime_type: "image/png"),
        Content.Resource.new(uri: "file:///test")
      ]

      json = Jason.encode!(contents)
      decoded = Jason.decode!(json)

      assert is_list(decoded)
      assert length(decoded) == 3
      assert Enum.at(decoded, 0)["type"] == "text"
      assert Enum.at(decoded, 1)["type"] == "image"
      assert Enum.at(decoded, 2)["type"] == "resource"
    end
  end
end
