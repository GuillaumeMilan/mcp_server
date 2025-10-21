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
end
