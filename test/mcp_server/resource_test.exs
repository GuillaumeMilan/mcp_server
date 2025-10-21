defmodule McpServer.ResourceTest do
  use ExUnit.Case, async: true

  alias McpServer.{Resource, ResourceTemplate}
  alias McpServer.Resource.{Content, ReadResult}

  describe "Resource.new/1" do
    test "creates a resource with minimal fields" do
      resource =
        Resource.new(
          name: "config",
          uri: "file:///app/config.json"
        )

      assert resource.name == "config"
      assert resource.uri == "file:///app/config.json"
      assert resource.description == nil
      assert resource.mime_type == nil
      assert resource.title == nil
    end

    test "creates a resource with all fields" do
      resource =
        Resource.new(
          name: "readme",
          uri: "file:///README.md",
          description: "Project README",
          mime_type: "text/markdown",
          title: "README"
        )

      assert resource.name == "readme"
      assert resource.uri == "file:///README.md"
      assert resource.description == "Project README"
      assert resource.mime_type == "text/markdown"
      assert resource.title == "README"
    end

    test "raises error when required fields are missing" do
      assert_raise KeyError, fn ->
        Resource.new(name: "config")
      end
    end
  end

  describe "ResourceTemplate.new/1" do
    test "creates a template with minimal fields" do
      template =
        ResourceTemplate.new(
          name: "user",
          uri_template: "https://api.example.com/users/{id}"
        )

      assert template.name == "user"
      assert template.uri_template == "https://api.example.com/users/{id}"
      assert template.description == nil
    end

    test "creates a template with all fields" do
      template =
        ResourceTemplate.new(
          name: "document",
          uri_template: "file:///docs/{category}/{id}.md",
          description: "Documentation files",
          mime_type: "text/markdown",
          title: "Docs"
        )

      assert template.name == "document"
      assert template.uri_template == "file:///docs/{category}/{id}.md"
      assert template.description == "Documentation files"
      assert template.mime_type == "text/markdown"
      assert template.title == "Docs"
    end

    test "raises error when uri_template is missing" do
      assert_raise KeyError, fn ->
        ResourceTemplate.new(name: "user")
      end
    end
  end

  describe "Content.new/1" do
    test "creates text content" do
      content =
        Content.new(
          name: "file.txt",
          uri: "file:///path/to/file.txt",
          mime_type: "text/plain",
          text: "File contents here"
        )

      assert content.name == "file.txt"
      assert content.uri == "file:///path/to/file.txt"
      assert content.mime_type == "text/plain"
      assert content.text == "File contents here"
      assert content.blob == nil
    end

    test "creates binary content with blob" do
      content =
        Content.new(
          name: "image.png",
          uri: "file:///images/logo.png",
          mime_type: "image/png",
          blob: "iVBORw0KGgo..."
        )

      assert content.name == "image.png"
      assert content.mime_type == "image/png"
      assert content.blob == "iVBORw0KGgo..."
      assert content.text == nil
    end

    test "creates content with title" do
      content =
        Content.new(
          name: "config.json",
          uri: "file:///app/config.json",
          title: "Application Configuration"
        )

      assert content.title == "Application Configuration"
    end

    test "raises error when required fields are missing" do
      assert_raise KeyError, fn ->
        Content.new(name: "file.txt")
      end
    end
  end

  describe "ReadResult.new/1" do
    test "creates an empty read result" do
      result = ReadResult.new(contents: [])

      assert result.contents == []
    end

    test "creates a read result with multiple contents" do
      content1 = Content.new(name: "file1.txt", uri: "file:///file1.txt")
      content2 = Content.new(name: "file2.txt", uri: "file:///file2.txt")

      result = ReadResult.new(contents: [content1, content2])

      assert length(result.contents) == 2
      assert hd(result.contents).name == "file1.txt"
    end

    test "raises error when contents is missing" do
      assert_raise KeyError, fn ->
        ReadResult.new([])
      end
    end
  end

  describe "Jason.Encoder for Resource" do
    test "encodes minimal resource" do
      resource = Resource.new(name: "config", uri: "file:///config.json")

      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "config"
      assert decoded["uri"] == "file:///config.json"
      refute Map.has_key?(decoded, "description")
      refute Map.has_key?(decoded, "mimeType")
      refute Map.has_key?(decoded, "title")
    end

    test "encodes resource with all fields" do
      resource =
        Resource.new(
          name: "readme",
          uri: "file:///README.md",
          description: "Project README",
          mime_type: "text/markdown",
          title: "README"
        )

      json = Jason.encode!(resource)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "readme"
      assert decoded["uri"] == "file:///README.md"
      assert decoded["description"] == "Project README"
      assert decoded["mimeType"] == "text/markdown"
      assert decoded["title"] == "README"
    end

    test "uses camelCase for mimeType" do
      resource =
        Resource.new(
          name: "test",
          uri: "file:///test",
          mime_type: "application/json"
        )

      json = Jason.encode!(resource)

      assert String.contains?(json, "mimeType")
      refute String.contains?(json, "mime_type")
    end
  end

  describe "Jason.Encoder for ResourceTemplate" do
    test "encodes minimal template" do
      template =
        ResourceTemplate.new(
          name: "user",
          uri_template: "https://api.example.com/users/{id}"
        )

      json = Jason.encode!(template)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "user"
      assert decoded["uriTemplate"] == "https://api.example.com/users/{id}"
      refute Map.has_key?(decoded, "description")
    end

    test "encodes template with all fields" do
      template =
        ResourceTemplate.new(
          name: "document",
          uri_template: "file:///docs/{id}.md",
          description: "Documentation",
          mime_type: "text/markdown",
          title: "Docs"
        )

      json = Jason.encode!(template)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "document"
      assert decoded["uriTemplate"] == "file:///docs/{id}.md"
      assert decoded["description"] == "Documentation"
      assert decoded["mimeType"] == "text/markdown"
      assert decoded["title"] == "Docs"
    end

    test "uses camelCase for uriTemplate" do
      template =
        ResourceTemplate.new(
          name: "test",
          uri_template: "file:///test/{id}"
        )

      json = Jason.encode!(template)

      assert String.contains?(json, "uriTemplate")
      refute String.contains?(json, "uri_template")
    end
  end

  describe "Jason.Encoder for Content" do
    test "encodes minimal content" do
      content = Content.new(name: "file.txt", uri: "file:///file.txt")

      json = Jason.encode!(content)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "file.txt"
      assert decoded["uri"] == "file:///file.txt"
      refute Map.has_key?(decoded, "text")
      refute Map.has_key?(decoded, "blob")
    end

    test "encodes text content" do
      content =
        Content.new(
          name: "file.txt",
          uri: "file:///file.txt",
          mime_type: "text/plain",
          text: "Hello world",
          title: "Test File"
        )

      json = Jason.encode!(content)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "file.txt"
      assert decoded["mimeType"] == "text/plain"
      assert decoded["text"] == "Hello world"
      assert decoded["title"] == "Test File"
      refute Map.has_key?(decoded, "blob")
    end

    test "encodes binary content" do
      content =
        Content.new(
          name: "image.png",
          uri: "file:///image.png",
          mime_type: "image/png",
          blob: "base64encodeddata"
        )

      json = Jason.encode!(content)
      decoded = Jason.decode!(json)

      assert decoded["blob"] == "base64encodeddata"
      refute Map.has_key?(decoded, "text")
    end
  end

  describe "Jason.Encoder for ReadResult" do
    test "encodes empty read result" do
      result = ReadResult.new(contents: [])

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["contents"] == []
    end

    test "encodes read result with contents" do
      content1 =
        Content.new(
          name: "file1.txt",
          uri: "file:///file1.txt",
          text: "Content 1"
        )

      content2 =
        Content.new(
          name: "file2.txt",
          uri: "file:///file2.txt",
          text: "Content 2"
        )

      result = ReadResult.new(contents: [content1, content2])

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert length(decoded["contents"]) == 2
      assert hd(decoded["contents"])["name"] == "file1.txt"
      assert hd(decoded["contents"])["text"] == "Content 1"
    end

    test "encodes nested content structures correctly" do
      content =
        Content.new(
          name: "data.json",
          uri: "file:///data.json",
          mime_type: "application/json",
          text: ~s({"key":"value"}),
          title: "Data"
        )

      result = ReadResult.new(contents: [content])

      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["contents"]
      first_content = hd(decoded["contents"])
      assert first_content["name"] == "data.json"
      assert first_content["mimeType"] == "application/json"
      assert first_content["text"] == ~s({"key":"value"})
      assert first_content["title"] == "Data"
    end
  end
end
