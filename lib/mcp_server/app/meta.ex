defmodule McpServer.App.Meta do
  @moduledoc """
  Metadata container for MCP App configuration on tools and resources.

  This struct wraps UI-related metadata that can be attached to tools
  (via `McpServer.App.UI`) or resources (via `McpServer.App.UIResourceMeta`).

  When serialized to JSON, it appears as the `_meta` field on tools and resources.

  ## Fields

  - `ui` - UI configuration, either a `McpServer.App.UI` for tools or
    `McpServer.App.UIResourceMeta` for resources

  ## Examples

      iex> McpServer.App.Meta.new(ui: McpServer.App.UI.new(resource_uri: "ui://dashboard"))
      %McpServer.App.Meta{ui: %McpServer.App.UI{resource_uri: "ui://dashboard", visibility: ["model", "app"]}}

      iex> McpServer.App.Meta.new()
      %McpServer.App.Meta{ui: nil}
  """

  defstruct [:ui]

  @type t :: %__MODULE__{
          ui: McpServer.App.UI.t() | McpServer.App.UIResourceMeta.t() | nil
        }

  @doc """
  Creates a new Meta struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:ui` - UI configuration struct (optional)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      ui: Keyword.get(opts, :ui)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.App.Meta do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "ui", value.ui)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
