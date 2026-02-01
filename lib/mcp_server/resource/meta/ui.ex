defmodule McpServer.Resource.Meta.UI do
  @moduledoc """
  UI metadata for resource definitions.

  Configures Content Security Policy, sandbox permissions, and rendering
  preferences for UI resources (resources with `ui://` URIs). This struct
  is used as the `ui` field inside `_meta` when attached to resources.

  ## Fields

  - `csp` - Content Security Policy configuration (`McpServer.Resource.Meta.UI.CSP`)
  - `permissions` - Sandbox permissions (`McpServer.Resource.Meta.UI.Permissions`)
  - `domain` - Optional dedicated domain for the view's sandbox origin
  - `prefers_border` - Visual boundary preference:
    - `true` - Request visible border and background
    - `false` - Request no visible border or background
    - `nil` - Let host decide

  ## Examples

      iex> McpServer.Resource.Meta.UI.new(
      ...>   csp: McpServer.Resource.Meta.UI.CSP.new(
      ...>     connect_domains: ["api.weather.com"],
      ...>     resource_domains: ["cdn.weather.com"]
      ...>   ),
      ...>   permissions: McpServer.Resource.Meta.UI.Permissions.new(camera: true),
      ...>   prefers_border: true
      ...> )
      %McpServer.Resource.Meta.UI{
        csp: %McpServer.Resource.Meta.UI.CSP{
          connect_domains: ["api.weather.com"],
          resource_domains: ["cdn.weather.com"]
        },
        permissions: %McpServer.Resource.Meta.UI.Permissions{camera: true},
        prefers_border: true
      }
  """

  alias McpServer.Resource.Meta.UI.CSP
  alias McpServer.Resource.Meta.UI.Permissions

  defstruct [:csp, :permissions, :domain, :prefers_border]

  @type t :: %__MODULE__{
          csp: CSP.t() | nil,
          permissions: Permissions.t() | nil,
          domain: String.t() | nil,
          prefers_border: boolean() | nil
        }

  @doc """
  Creates a new Resource.Meta.UI struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:csp` - `McpServer.Resource.Meta.UI.CSP` struct (optional)
    - `:permissions` - `McpServer.Resource.Meta.UI.Permissions` struct (optional)
    - `:domain` - Dedicated sandbox domain (optional)
    - `:prefers_border` - Border preference boolean (optional)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      csp: Keyword.get(opts, :csp),
      permissions: Keyword.get(opts, :permissions),
      domain: Keyword.get(opts, :domain),
      prefers_border: Keyword.get(opts, :prefers_border)
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Resource.Meta.UI do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "csp", value.csp)
    map = maybe_put(map, "permissions", value.permissions)
    map = maybe_put(map, "domain", value.domain)
    map = maybe_put(map, "prefersBorder", value.prefers_border)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
