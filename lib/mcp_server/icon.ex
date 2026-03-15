defmodule McpServer.Icon do
  @moduledoc """
  Represents an icon for tools, prompts, and resources.

  Icons provide a standardized way for servers to expose visual identifiers
  for their resources, tools, prompts, and implementations.

  ## Fields

  - `src` - URL of the icon image (required)
  - `mime_type` - MIME type of the icon (optional, e.g., "image/png", "image/svg+xml")
  - `sizes` - List of size strings (optional, e.g., ["48x48", "96x96"])

  ## Examples

      iex> McpServer.Icon.new(src: "https://example.com/icon.png")
      %McpServer.Icon{src: "https://example.com/icon.png", mime_type: nil, sizes: []}

      iex> McpServer.Icon.new(
      ...>   src: "https://example.com/icon.png",
      ...>   mime_type: "image/png",
      ...>   sizes: ["48x48", "96x96"]
      ...> )
      %McpServer.Icon{
        src: "https://example.com/icon.png",
        mime_type: "image/png",
        sizes: ["48x48", "96x96"]
      }
  """

  @enforce_keys [:src]
  defstruct [:src, :mime_type, sizes: []]

  @type t :: %__MODULE__{
          src: String.t(),
          mime_type: String.t() | nil,
          sizes: [String.t()]
        }

  @doc """
  Creates a new Icon struct.

  ## Parameters

  - `opts` - Keyword list of icon options:
    - `:src` (required) - URL of the icon image
    - `:mime_type` - MIME type of the icon
    - `:sizes` - List of size strings (default: [])

  ## Examples

      iex> McpServer.Icon.new(src: "https://example.com/icon.png")
      %McpServer.Icon{src: "https://example.com/icon.png", mime_type: nil, sizes: []}

      iex> McpServer.Icon.new(
      ...>   src: "https://example.com/icon.png",
      ...>   mime_type: "image/png",
      ...>   sizes: ["48x48"]
      ...> )
      %McpServer.Icon{src: "https://example.com/icon.png", mime_type: "image/png", sizes: ["48x48"]}
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    src = Keyword.fetch!(opts, :src)

    unless is_binary(src) do
      raise ArgumentError, "src must be a string"
    end

    mime_type = Keyword.get(opts, :mime_type)

    if mime_type != nil and not is_binary(mime_type) do
      raise ArgumentError, "mime_type must be a string or nil"
    end

    sizes = Keyword.get(opts, :sizes, [])

    unless is_list(sizes) do
      raise ArgumentError, "sizes must be a list"
    end

    %__MODULE__{src: src, mime_type: mime_type, sizes: sizes}
  end
end

defimpl Jason.Encoder, for: McpServer.Icon do
  def encode(value, opts) do
    map = %{"src" => value.src}
    map = maybe_put(map, "mimeType", value.mime_type)

    map =
      case value.sizes do
        [] -> map
        sizes -> Map.put(map, "sizes", sizes)
      end

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
