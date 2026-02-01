defmodule McpServer.Tool.Meta do
  @moduledoc """
  Metadata container for tool UI configuration.

  Wraps `McpServer.Tool.Meta.UI` and is serialized as the `_meta` field on tools.

  ## Fields

  - `ui` - UI configuration (`McpServer.Tool.Meta.UI`)

  ## Examples

      iex> McpServer.Tool.Meta.new(ui: McpServer.Tool.Meta.UI.new(resource_uri: "ui://dashboard"))
      %McpServer.Tool.Meta{ui: %McpServer.Tool.Meta.UI{resource_uri: "ui://dashboard", visibility: [:model, :app]}}

      iex> McpServer.Tool.Meta.new()
      %McpServer.Tool.Meta{ui: nil}
  """

  defstruct [:ui]

  @type t :: %__MODULE__{
          ui: McpServer.Tool.Meta.UI.t() | nil
        }

  @doc """
  Creates a new Tool.Meta struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:ui` - `McpServer.Tool.Meta.UI` struct (optional)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      ui: Keyword.get(opts, :ui)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Tool.Meta do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "ui", value.ui)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
