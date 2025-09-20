defmodule McpServer.ResourceTest do
  use ExUnit.Case, async: true
  alias McpServer.Resource

  test "content/3 builds text content with provided fields" do
    res =
      Resource.content(
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
      Resource.content("image.png", "file:///tmp/image.png", mimeType: "image/png", blob: blob)

    assert res["name"] == "image.png"
    assert res["uri"] == "file:///tmp/image.png"
    assert res["mimeType"] == "image/png"
    assert res["blob"] == Base.encode64(blob)
    refute Map.has_key?(res, "text")
  end

  test "content/3 raises when blob is not binary" do
    assert_raise ArgumentError, ":blob option must be a binary", fn ->
      Resource.content("bad", "file://bad", blob: :not_binary)
    end
  end
end
