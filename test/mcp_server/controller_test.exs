defmodule McpServer.ControllerTest do
  use ExUnit.Case, async: true
  import McpServer.Controller

  doctest McpServer.Controller

  test "content/3 builds text content with provided fields" do
    res =
      content(
        "main.rs",
        "file:///project/src/main.rs",
        mimeType: "plain/text",
        text: "<actual content of the file>...",
        title: "Main file of the code base"
      )

    # Result is now a Content struct
    assert %McpServer.Resource.Content{} = res
    assert res.name == "main.rs"
    assert res.uri == "file:///project/src/main.rs"
    assert res.mime_type == "plain/text"
    assert res.text == "<actual content of the file>..."
    assert res.title == "Main file of the code base"

    # Verify JSON encoding works correctly
    json = Jason.encode!(res)
    decoded = Jason.decode!(json)
    assert decoded["name"] == "main.rs"
    assert decoded["mimeType"] == "plain/text"
  end

  test "content/3 encodes blob binary as base64" do
    blob = <<255, 216, 255>>

    res =
      content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: blob)

    # Result is now a Content struct
    assert %McpServer.Resource.Content{} = res
    assert res.name == "image.png"
    assert res.uri == "file:///tmp/image.png"
    assert res.mime_type == "image/png"
    assert res.blob == Base.encode64(blob)
    assert res.text == nil

    # Verify JSON encoding works correctly
    json = Jason.encode!(res)
    decoded = Jason.decode!(json)
    assert decoded["blob"] == Base.encode64(blob)
    refute Map.has_key?(decoded, "text")
  end

  test "content/3 raises when blob is not binary" do
    assert_raise ArgumentError, ":blob option must be a binary", fn ->
      content("bad", "file://bad", blob: :not_binary)
    end
  end

  # Test prompt functionality separately for now until we implement the macro
  describe "message/3" do
    test "creates proper message structure" do
      msg = message("user", "text", "Hello world!")

      # Result is now a Message struct
      assert %McpServer.Prompt.Message{} = msg
      assert msg.role == "user"
      assert msg.content.type == "text"
      assert msg.content.text == "Hello world!"

      # Verify JSON encoding works correctly
      json = Jason.encode!(msg)
      decoded = Jason.decode!(json)
      assert decoded["role"] == "user"
      assert decoded["content"]["type"] == "text"
      assert decoded["content"]["text"] == "Hello world!"
    end
  end

  describe "completion/2" do
    test "creates proper completion structure without defaults" do
      comp = completion(["Alice", "Bob"], [])

      # Result is now a Completion struct
      assert %McpServer.Completion{} = comp
      assert comp.values == ["Alice", "Bob"]
      assert comp.total == nil
      assert comp.has_more == nil

      # Verify JSON encoding works correctly
      json = Jason.encode!(comp)
      decoded = Jason.decode!(json)
      assert decoded["values"] == ["Alice", "Bob"]
      refute Map.has_key?(decoded, "total")
      refute Map.has_key?(decoded, "hasMore")
    end

    test "creates proper completion structure with options" do
      comp = completion(["Alice", "Bob"], total: 10, has_more: true)

      # Result is now a Completion struct
      assert %McpServer.Completion{} = comp
      assert comp.values == ["Alice", "Bob"]
      assert comp.total == 10
      assert comp.has_more == true

      # Verify JSON encoding works correctly
      json = Jason.encode!(comp)
      decoded = Jason.decode!(json)
      assert decoded["values"] == ["Alice", "Bob"]
      assert decoded["total"] == 10
      assert decoded["hasMore"] == true
    end
  end

  describe "text_content/1" do
    test "creates text content struct with correct structure" do
      result = text_content("Hello, World!")

      assert %McpServer.Tool.Content.Text{} = result
      assert result.text == "Hello, World!"
    end

    test "creates text content with empty string" do
      result = text_content("")

      assert %McpServer.Tool.Content.Text{} = result
      assert result.text == ""
    end

    test "creates text content with multiline text" do
      multiline = """
      Line 1
      Line 2
      Line 3
      """

      result = text_content(multiline)

      assert %McpServer.Tool.Content.Text{} = result
      assert result.text == multiline
    end

    test "creates text content with unicode characters" do
      result = text_content("Hello 世界 🌍")

      assert %McpServer.Tool.Content.Text{} = result
      assert result.text == "Hello 世界 🌍"
    end

    test "struct can be JSON encoded to correct format" do
      result = text_content("Test message")
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "text"
      assert decoded["text"] == "Test message"
    end
  end

  describe "image_content/2" do
    test "creates image content struct with correct structure" do
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      result = image_content(image_data, "image/png")

      assert %McpServer.Tool.Content.Image{} = result
      assert result.data == image_data
      assert result.mime_type == "image/png"
    end

    test "creates image content with different mime types" do
      image_data = <<255, 216, 255, 224>>
      result = image_content(image_data, "image/jpeg")

      assert %McpServer.Tool.Content.Image{} = result
      assert result.data == image_data
      assert result.mime_type == "image/jpeg"
    end

    test "creates image content with empty binary" do
      result = image_content(<<>>, "image/gif")

      assert %McpServer.Tool.Content.Image{} = result
      assert result.data == <<>>
      assert result.mime_type == "image/gif"
    end

    test "struct stores raw binary data (not base64)" do
      binary = <<255, 216, 255>>
      result = image_content(binary, "image/png")

      # Data is stored as-is in the struct
      assert result.data == binary
    end

    test "struct JSON encodes with base64 data" do
      image_data = <<1, 2, 3, 4, 5>>
      result = image_content(image_data, "image/png")
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      # JSON encoding converts to base64
      assert decoded["type"] == "image"
      assert decoded["data"] == Base.encode64(image_data)
      assert decoded["mimeType"] == "image/png"
    end
  end

  describe "resource_content/2" do
    test "creates resource content struct with URI only" do
      result = resource_content("file:///path/to/file.txt")

      assert %McpServer.Tool.Content.Resource{} = result
      assert result.uri == "file:///path/to/file.txt"
      assert result.mime_type == nil
      assert result.text == nil
      assert result.blob == nil
    end

    test "creates resource content with text" do
      result =
        resource_content("file:///data.json",
          mimeType: "application/json",
          text: ~s({"key": "value"})
        )

      assert %McpServer.Tool.Content.Resource{} = result
      assert result.uri == "file:///data.json"
      assert result.mime_type == "application/json"
      assert result.text == ~s({"key": "value"})
      assert result.blob == nil
    end

    test "creates resource content with blob" do
      blob = <<255, 216, 255>>

      result =
        resource_content("file:///image.png", mimeType: "image/png", blob: blob)

      assert %McpServer.Tool.Content.Resource{} = result
      assert result.uri == "file:///image.png"
      assert result.mime_type == "image/png"
      assert result.blob == blob
      assert result.text == nil
    end

    test "creates resource content with both text and blob" do
      blob = <<1, 2, 3>>

      result =
        resource_content("file:///file.bin",
          mimeType: "application/octet-stream",
          text: "description",
          blob: blob
        )

      assert %McpServer.Tool.Content.Resource{} = result
      assert result.uri == "file:///file.bin"
      assert result.mime_type == "application/octet-stream"
      assert result.text == "description"
      assert result.blob == blob
    end

    test "struct stores optional fields as nil when not provided" do
      result = resource_content("file:///minimal.txt", mimeType: "text/plain")

      assert result.uri == "file:///minimal.txt"
      assert result.mime_type == "text/plain"
      assert result.text == nil
      assert result.blob == nil
    end

    test "raises when blob is not binary" do
      assert_raise ArgumentError, "blob must be a binary or nil", fn ->
        resource_content("file:///bad", blob: :not_binary)
      end

      assert_raise ArgumentError, "blob must be a binary or nil", fn ->
        resource_content("file:///bad", blob: 123)
      end

      assert_raise ArgumentError, "blob must be a binary or nil", fn ->
        resource_content("file:///bad", blob: ["not", "binary"])
      end
    end

    test "struct JSON encodes to correct format" do
      result =
        resource_content("file:///test.txt", mimeType: "text/plain", text: "content")

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "resource"
      assert decoded["resource"]["uri"] == "file:///test.txt"
      assert decoded["resource"]["mimeType"] == "text/plain"
      assert decoded["resource"]["text"] == "content"
      refute Map.has_key?(decoded["resource"], "blob")
    end

    test "struct JSON encoding only includes non-nil fields" do
      result = resource_content("file:///minimal.txt")

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["resource"]["uri"] == "file:///minimal.txt"
      refute Map.has_key?(decoded["resource"], "mimeType")
      refute Map.has_key?(decoded["resource"], "text")
      refute Map.has_key?(decoded["resource"], "blob")
    end

    test "handles various URI schemes" do
      http_result = resource_content("http://example.com/file.txt")
      https_result = resource_content("https://example.com/file.txt")
      ftp_result = resource_content("ftp://server.com/file.txt")

      assert http_result.uri == "http://example.com/file.txt"
      assert https_result.uri == "https://example.com/file.txt"
      assert ftp_result.uri == "ftp://server.com/file.txt"
    end
  end

  describe "tool content helpers integration" do
    test "can combine multiple content types in a list" do
      image_data = <<255, 216, 255>>

      contents = [
        text_content("Analysis complete"),
        image_content(image_data, "image/jpeg"),
        resource_content("file:///report.pdf", mimeType: "application/pdf")
      ]

      assert length(contents) == 3
      assert %McpServer.Tool.Content.Text{} = Enum.at(contents, 0)
      assert %McpServer.Tool.Content.Image{} = Enum.at(contents, 1)
      assert %McpServer.Tool.Content.Resource{} = Enum.at(contents, 2)

      # Verify all can be JSON encoded together
      json = Jason.encode!(contents)
      decoded = Jason.decode!(json)

      assert length(decoded) == 3
      assert Enum.at(decoded, 0)["type"] == "text"
      assert Enum.at(decoded, 1)["type"] == "image"
      assert Enum.at(decoded, 2)["type"] == "resource"
    end

    test "single content item can be returned" do
      result = text_content("Simple response")

      # Can be used as a single item
      assert %McpServer.Tool.Content.Text{} = result
      assert result.text == "Simple response"
    end

    test "structs match MCP protocol format when JSON encoded" do
      # According to MCP spec, tool results should have content array with type field
      result = text_content("Hello")

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      # Verify it has the required fields for MCP protocol
      assert Map.has_key?(decoded, "type")
      assert is_binary(decoded["type"])

      # For text content
      assert Map.has_key?(decoded, "text")
      assert is_binary(decoded["text"])
    end
  end
end
