defmodule McpServer.Tool.Content do
  @moduledoc """
  Structs and helper functions for representing tool result content items.

  This module provides typed structs and convenience functions for different
  types of content that can be returned from tool functions, following the
  MCP protocol specification.

  ## Content Types

  - `Text` - Text content
  - `Image` - Image content with base64-encoded data
  - `Resource` - Embedded resource content

  ## Usage

  You can alias this module and use the helper functions to build tool results:

      alias McpServer.Tool.Content, as: ToolContent

      def search_tool(_conn, %{"query" => query}) do
        [
          ToolContent.text("Found 5 results for: \#{query}"),
          ToolContent.text("Result 1: ..."),
          ToolContent.text("Result 2: ...")
        ]
      end

      def generate_chart(_conn, %{"data" => data}) do
        chart_image = create_chart(data)
        [
          ToolContent.text("Chart generated successfully"),
          ToolContent.image(chart_image, "image/png")
        ]
      end

      def read_file(_conn, %{"path" => path}) do
        [ToolContent.resource("file://\#{path}", text: File.read!(path), mimeType: "text/plain")]
      end

  ## Low-level Struct API

      iex> alias McpServer.Tool.Content
      iex> text = Content.Text.new(text: "Hello, World!")
      iex> text.text
      "Hello, World!"

      iex> image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      iex> image = Content.Image.new(data: image_data, mime_type: "image/png")
      iex> image.mime_type
      "image/png"

      iex> resource = Content.Resource.new(uri: "file:///path/to/file.txt")
      iex> resource.uri
      "file:///path/to/file.txt"
  """

  @doc """
  Creates a text content item for tool responses.

  Returns a `McpServer.Tool.Content.Text` struct.

  ## Parameters

  - `text` (string): the text content to return

  ## Examples

      iex> McpServer.Tool.Content.text("Hello, World!")
      %McpServer.Tool.Content.Text{text: "Hello, World!"}

      iex> McpServer.Tool.Content.text("Operation completed successfully")
      %McpServer.Tool.Content.Text{text: "Operation completed successfully"}
  """
  @spec text(String.t()) :: McpServer.Tool.Content.Text.t()
  def text(text) when is_binary(text) do
    McpServer.Tool.Content.Text.new(text: text)
  end

  @doc """
  Creates an image content item for tool responses.

  Returns a `McpServer.Tool.Content.Image` struct.
  The image data will be automatically base64-encoded during JSON serialization.

  ## Parameters

  - `data` (binary): the raw image data
  - `mime_type` (string): the MIME type of the image (e.g., "image/png", "image/jpeg")

  ## Examples

      iex> image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      iex> McpServer.Tool.Content.image(image_data, "image/png")
      %McpServer.Tool.Content.Image{data: <<137, 80, 78, 71, 13, 10, 26, 10>>, mime_type: "image/png"}
  """
  @spec image(binary(), String.t()) :: McpServer.Tool.Content.Image.t()
  def image(data, mime_type) when is_binary(data) and is_binary(mime_type) do
    McpServer.Tool.Content.Image.new(data: data, mime_type: mime_type)
  end

  @doc """
  Creates an embedded resource content item for tool responses.

  Returns a `McpServer.Tool.Content.Resource` struct.

  ## Parameters

  - `uri` (string): the URI of the resource
  - `opts` (keyword list): optional keys include:
    - `:mimeType` - MIME type of the resource
    - `:text` - textual content of the resource
    - `:blob` - binary content; base64-encoded during JSON serialization

  ## Examples

      iex> McpServer.Tool.Content.resource("file:///path/to/file.txt")
      %McpServer.Tool.Content.Resource{uri: "file:///path/to/file.txt", text: nil, blob: nil, mime_type: nil}

      iex> McpServer.Tool.Content.resource("file:///data.json", mimeType: "application/json", text: ~s({"key": "value"}))
      %McpServer.Tool.Content.Resource{
        uri: "file:///data.json",
        mime_type: "application/json",
        text: ~s({"key": "value"}),
        blob: nil
      }

      iex> McpServer.Tool.Content.resource("file:///image.png", mimeType: "image/png", blob: <<255, 216, 255>>)
      %McpServer.Tool.Content.Resource{
        uri: "file:///image.png",
        mime_type: "image/png",
        text: nil,
        blob: <<255, 216, 255>>
      }
  """
  @spec resource(String.t(), keyword()) :: McpServer.Tool.Content.Resource.t()
  def resource(uri, opts \\ []) when is_binary(uri) and is_list(opts) do
    mime_type = Keyword.get(opts, :mimeType) || Keyword.get(opts, :mime_type)
    text = Keyword.get(opts, :text)
    blob = Keyword.get(opts, :blob)

    McpServer.Tool.Content.Resource.new(
      uri: uri,
      mime_type: mime_type,
      text: text,
      blob: blob
    )
  end

  defmodule Text do
    @moduledoc """
    Represents text content in a tool result.

    ## Fields

    - `text` - The text content (required)

    ## Examples

        iex> text = McpServer.Tool.Content.Text.new(text: "Hello!")
        iex> text.text
        "Hello!"
    """

    @enforce_keys [:text]
    defstruct [:text]

    @type t :: %__MODULE__{
            text: String.t()
          }

    @doc """
    Creates a new Text content struct.

    ## Parameters

    - `opts` - Keyword list with required `:text` field

    ## Examples

        iex> McpServer.Tool.Content.Text.new(text: "Hello, World!")
        %McpServer.Tool.Content.Text{text: "Hello, World!"}
    """
    @spec new(keyword()) :: t()
    def new(opts) when is_list(opts) do
      text = Keyword.fetch!(opts, :text)

      unless is_binary(text) do
        raise ArgumentError, "text must be a string"
      end

      %__MODULE__{text: text}
    end
  end

  defmodule Image do
    @moduledoc """
    Represents image content in a tool result.

    The image data is stored as-is (not base64-encoded in the struct).
    Base64 encoding happens during JSON serialization.

    ## Fields

    - `data` - The raw binary image data (required)
    - `mime_type` - The MIME type of the image (required)

    ## Examples

        iex> image_data = <<137, 80, 78, 71>>
        iex> image = McpServer.Tool.Content.Image.new(data: image_data, mime_type: "image/png")
        iex> image.mime_type
        "image/png"
    """

    @enforce_keys [:data, :mime_type]
    defstruct [:data, :mime_type]

    @type t :: %__MODULE__{
            data: binary(),
            mime_type: String.t()
          }

    @doc """
    Creates a new Image content struct.

    ## Parameters

    - `opts` - Keyword list with required `:data` and `:mime_type` fields

    ## Examples

        iex> image_data = <<255, 216, 255>>
        iex> McpServer.Tool.Content.Image.new(data: image_data, mime_type: "image/jpeg")
        %McpServer.Tool.Content.Image{data: <<255, 216, 255>>, mime_type: "image/jpeg"}
    """
    @spec new(keyword()) :: t()
    def new(opts) when is_list(opts) do
      data = Keyword.fetch!(opts, :data)
      mime_type = Keyword.fetch!(opts, :mime_type)

      unless is_binary(data) do
        raise ArgumentError, "data must be a binary"
      end

      unless is_binary(mime_type) do
        raise ArgumentError, "mime_type must be a string"
      end

      %__MODULE__{data: data, mime_type: mime_type}
    end
  end

  defmodule Resource do
    @moduledoc """
    Represents an embedded resource in a tool result.

    ## Fields

    - `uri` - The URI of the resource (required)
    - `text` - Textual content of the resource (optional)
    - `blob` - Binary content of the resource, stored as-is (optional)
    - `mime_type` - MIME type of the resource (optional)

    The blob data is stored as-is (not base64-encoded in the struct).
    Base64 encoding happens during JSON serialization.

    ## Examples

        iex> resource = McpServer.Tool.Content.Resource.new(uri: "file:///path/to/file.txt")
        iex> resource.uri
        "file:///path/to/file.txt"

        iex> resource = McpServer.Tool.Content.Resource.new(
        ...>   uri: "file:///data.json",
        ...>   text: ~s({"key": "value"}),
        ...>   mime_type: "application/json"
        ...> )
        iex> resource.text
        ~s({"key": "value"})
    """

    @enforce_keys [:uri]
    defstruct [:uri, :text, :blob, :mime_type]

    @type t :: %__MODULE__{
            uri: String.t(),
            text: String.t() | nil,
            blob: binary() | nil,
            mime_type: String.t() | nil
          }

    @doc """
    Creates a new Resource content struct.

    ## Parameters

    - `opts` - Keyword list with required `:uri` field and optional `:text`, `:blob`, `:mime_type` fields

    ## Examples

        iex> McpServer.Tool.Content.Resource.new(uri: "file:///test.txt")
        %McpServer.Tool.Content.Resource{uri: "file:///test.txt", text: nil, blob: nil, mime_type: nil}

        iex> McpServer.Tool.Content.Resource.new(
        ...>   uri: "file:///test.txt",
        ...>   text: "content",
        ...>   mime_type: "text/plain"
        ...> )
        %McpServer.Tool.Content.Resource{
          uri: "file:///test.txt",
          text: "content",
          blob: nil,
          mime_type: "text/plain"
        }
    """
    @spec new(keyword()) :: t()
    def new(opts) when is_list(opts) do
      uri = Keyword.fetch!(opts, :uri)
      text = Keyword.get(opts, :text)
      blob = Keyword.get(opts, :blob)
      mime_type = Keyword.get(opts, :mime_type)

      unless is_binary(uri) do
        raise ArgumentError, "uri must be a string"
      end

      if text != nil and not is_binary(text) do
        raise ArgumentError, "text must be a string or nil"
      end

      if blob != nil and not is_binary(blob) do
        raise ArgumentError, "blob must be a binary or nil"
      end

      if mime_type != nil and not is_binary(mime_type) do
        raise ArgumentError, "mime_type must be a string or nil"
      end

      %__MODULE__{uri: uri, text: text, blob: blob, mime_type: mime_type}
    end
  end

  # Jason.Encoder implementations

  defimpl Jason.Encoder, for: McpServer.Tool.Content.Text do
    def encode(value, opts) do
      map = %{
        "type" => "text",
        "text" => value.text
      }

      Jason.Encode.map(map, opts)
    end
  end

  defimpl Jason.Encoder, for: McpServer.Tool.Content.Image do
    def encode(value, opts) do
      map = %{
        "type" => "image",
        "data" => Base.encode64(value.data),
        "mimeType" => value.mime_type
      }

      Jason.Encode.map(map, opts)
    end
  end

  defimpl Jason.Encoder, for: McpServer.Tool.Content.Resource do
    def encode(value, opts) do
      # Build the resource map, only including non-nil fields
      resource =
        %{"uri" => value.uri}
        |> maybe_put("mimeType", value.mime_type)
        |> maybe_put("text", value.text)
        |> maybe_put("blob", value.blob && Base.encode64(value.blob))

      map = %{
        "type" => "resource",
        "resource" => resource
      }

      Jason.Encode.map(map, opts)
    end

    # Helper function to conditionally add fields to a map
    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end
end
