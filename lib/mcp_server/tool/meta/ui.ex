defmodule McpServer.Tool.Meta.UI do
  @moduledoc """
  UI metadata for tool definitions.

  Links tools to UI resources and controls tool visibility. This struct is used
  as the `ui` field inside `_meta` when attached to tools.

  ## Visibility

  Visibility is specified as a list of `t:visibility/0` values:

  - `:model` - Tool visible to and callable by the agent/model
  - `:app` - Tool callable by the app (UI view) from this server only

  ## Examples

      # Tool visible to both model and app (default)
      iex> McpServer.Tool.Meta.UI.new(resource_uri: "ui://weather-server/dashboard")
      %McpServer.Tool.Meta.UI{resource_uri: "ui://weather-server/dashboard", visibility: [:model, :app]}

      # App-only tool (hidden from model)
      iex> McpServer.Tool.Meta.UI.new(resource_uri: "ui://weather-server/dashboard", visibility: [:app])
      %McpServer.Tool.Meta.UI{resource_uri: "ui://weather-server/dashboard", visibility: [:app]}
  """

  @type visibility :: :model | :app

  defstruct [
    :resource_uri,
    visibility: [:model, :app]
  ]

  @type t :: %__MODULE__{
          resource_uri: String.t() | nil,
          visibility: [visibility()]
        }

  @doc """
  Creates a new UI metadata struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:resource_uri` - URI of the UI resource (optional)
    - `:visibility` - List of `t:visibility/0` targets (default: `[:model, :app]`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      resource_uri: Keyword.get(opts, :resource_uri),
      visibility: Keyword.get(opts, :visibility, [:model, :app])
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Tool.Meta.UI do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "resourceUri", value.resource_uri)

    map =
      maybe_put(map, "visibility", Enum.map(value.visibility, &Atom.to_string/1))

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
