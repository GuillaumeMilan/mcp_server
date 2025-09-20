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

    assert res["name"] == "main.rs"
    assert res["uri"] == "file:///project/src/main.rs"
    assert res["mimeType"] == "plain/text"
    assert res["text"] == "<actual content of the file>..."
    assert res["title"] == "Main file of the code base"
  end

  test "content/3 encodes blob binary as base64" do
    blob = <<255, 216, 255>>

    res =
      content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: blob)

    assert res["name"] == "image.png"
    assert res["uri"] == "file:///tmp/image.png"
    assert res["mimeType"] == "image/png"
    assert res["blob"] == Base.encode64(blob)
    refute Map.has_key?(res, "text")
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

      assert msg == %{
               "role" => "user",
               "content" => %{
                 "type" => "text",
                 "text" => "Hello world!"
               }
             }
    end
  end

  describe "completion/2" do
    test "creates proper completion structure without defaults" do
      comp = completion(["Alice", "Bob"], [])

      assert comp == %{
               "values" => ["Alice", "Bob"]
             }
    end

    test "creates proper completion structure with options" do
      comp = completion(["Alice", "Bob"], total: 10, has_more: true)

      assert comp == %{
               "values" => ["Alice", "Bob"],
               "total" => 10,
               "hasMore" => true
             }
    end
  end
end
