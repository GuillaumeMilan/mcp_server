defmodule McpServer.Tool.Content do
  @moduledoc """
  Structs for representing tool result content items.

  This module provides typed structs for different types of content that can be
  returned from tool functions, following the MCP protocol specification.

  ## Content Types

  - `Text` - Text content
  - `Image` - Image content with base64-encoded data
  - `Resource` - Embedded resource content

  ## Examples

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
