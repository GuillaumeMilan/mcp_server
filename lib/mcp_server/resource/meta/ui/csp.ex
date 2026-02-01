defmodule McpServer.Resource.Meta.UI.CSP do
  @moduledoc """
  Content Security Policy configuration for UI resources.

  Declares which external domains are allowed for various resource types
  in sandboxed iframes. These fields map to CSP directives:

  | Field | CSP Directive |
  |-------|--------------:|
  | `connect_domains` | `connect-src` (API calls, WebSockets) |
  | `resource_domains` | `script-src`, `style-src`, `img-src`, `media-src`, `font-src` |
  | `frame_domains` | `frame-src` |
  | `base_uri_domains` | `base-uri` |

  ## Examples

      iex> McpServer.Resource.Meta.UI.CSP.new(
      ...>   connect_domains: ["api.weather.com"],
      ...>   resource_domains: ["cdn.weather.com"]
      ...> )
      %McpServer.Resource.Meta.UI.CSP{
        connect_domains: ["api.weather.com"],
        resource_domains: ["cdn.weather.com"]
      }
  """

  defstruct [
    connect_domains: [],
    resource_domains: [],
    frame_domains: [],
    base_uri_domains: []
  ]

  @type t :: %__MODULE__{
          connect_domains: list(String.t()),
          resource_domains: list(String.t()),
          frame_domains: list(String.t()),
          base_uri_domains: list(String.t())
        }

  @doc """
  Creates a new CSP struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:connect_domains` - Domains for network requests (default: `[]`)
    - `:resource_domains` - Domains for static resources (default: `[]`)
    - `:frame_domains` - Domains for nested iframes (default: `[]`)
    - `:base_uri_domains` - Base URI allowlist (default: `[]`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      connect_domains: Keyword.get(opts, :connect_domains, []),
      resource_domains: Keyword.get(opts, :resource_domains, []),
      frame_domains: Keyword.get(opts, :frame_domains, []),
      base_uri_domains: Keyword.get(opts, :base_uri_domains, [])
    }
  end
end

defimpl Jason.Encoder, for: McpServer.Resource.Meta.UI.CSP do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "connectDomains", value.connect_domains)
    map = maybe_put(map, "resourceDomains", value.resource_domains)
    map = maybe_put(map, "frameDomains", value.frame_domains)
    map = maybe_put(map, "baseUriDomains", value.base_uri_domains)

    Jason.Encode.map(map, opts)
  end

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
