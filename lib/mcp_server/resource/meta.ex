defmodule McpServer.Resource.Meta do
  @moduledoc """
  Metadata container for resource UI configuration.

  Wraps `McpServer.Resource.Meta.UI` and is serialized as the `_meta` field on resources.

  ## Fields

  - `ui` - UI configuration (`McpServer.Resource.Meta.UI`)

  ## Examples

      iex> McpServer.Resource.Meta.new(ui: McpServer.Resource.Meta.UI.new(domain: "example.com"))
      %McpServer.Resource.Meta{ui: %McpServer.Resource.Meta.UI{domain: "example.com"}}

      iex> McpServer.Resource.Meta.new()
      %McpServer.Resource.Meta{ui: nil}
  """

  defstruct [:ui]

  @type t :: %__MODULE__{
          ui: McpServer.Resource.Meta.UI.t() | nil
        }

  @doc """
  Creates a new Resource.Meta struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:ui` - `McpServer.Resource.Meta.UI` struct (optional)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      ui: Keyword.get(opts, :ui)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Resource.Meta do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "ui", value.ui)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
