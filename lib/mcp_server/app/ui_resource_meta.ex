defmodule McpServer.App.UIResourceMeta do
  @moduledoc """
  UI metadata for resource definitions.

  Configures Content Security Policy, sandbox permissions, and rendering
  preferences for UI resources (resources with `ui://` URIs). This struct
  is used as the `ui` field inside `McpServer.App.Meta` when attached to resources.

  ## Fields

  - `csp` - Content Security Policy configuration map:
    - `:connect_domains` - Domains allowed for network requests (fetch/XHR/WebSocket)
    - `:resource_domains` - Domains allowed for static resources (images, scripts, stylesheets, fonts)
    - `:frame_domains` - Domains allowed for nested iframes
    - `:base_uri_domains` - Base URI allowlist
  - `permissions` - Sandbox permissions requested by the UI:
    - `:camera` - Camera access (`%{}` to request)
    - `:microphone` - Microphone access (`%{}` to request)
    - `:geolocation` - Geolocation access (`%{}` to request)
    - `:clipboard_write` - Clipboard write access (`%{}` to request)
  - `domain` - Optional dedicated domain for the view's sandbox origin
  - `prefers_border` - Visual boundary preference:
    - `true` - Request visible border and background
    - `false` - Request no visible border or background
    - `nil` - Let host decide

  ## Examples

      iex> McpServer.App.UIResourceMeta.new(
      ...>   csp: %{connect_domains: ["api.weather.com"], resource_domains: ["cdn.weather.com"]},
      ...>   permissions: %{camera: %{}},
      ...>   prefers_border: true
      ...> )
      %McpServer.App.UIResourceMeta{
        csp: %{connect_domains: ["api.weather.com"], resource_domains: ["cdn.weather.com"]},
        permissions: %{camera: %{}},
        prefers_border: true
      }
  """

  defstruct [:csp, :permissions, :domain, :prefers_border]

  @type csp :: %{
          optional(:connect_domains) => list(String.t()),
          optional(:resource_domains) => list(String.t()),
          optional(:frame_domains) => list(String.t()),
          optional(:base_uri_domains) => list(String.t())
        }

  @type permissions :: %{
          optional(:camera) => map(),
          optional(:microphone) => map(),
          optional(:geolocation) => map(),
          optional(:clipboard_write) => map()
        }

  @type t :: %__MODULE__{
          csp: csp() | nil,
          permissions: permissions() | nil,
          domain: String.t() | nil,
          prefers_border: boolean() | nil
        }

  @doc """
  Creates a new UIResourceMeta struct.

  ## Parameters

  - `opts` - Keyword list of options:
    - `:csp` - CSP configuration map (optional)
    - `:permissions` - Sandbox permissions map (optional)
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

defimpl Jason.Encoder, for: McpServer.App.UIResourceMeta do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "csp", encode_csp(value.csp))
    map = maybe_put(map, "permissions", encode_permissions(value.permissions))
    map = maybe_put(map, "domain", value.domain)
    map = maybe_put(map, "prefersBorder", value.prefers_border)

    Jason.Encode.map(map, opts)
  end

  defp encode_csp(nil), do: nil

  defp encode_csp(csp) when is_map(csp) do
    map = %{}

    map = maybe_put(map, "connectDomains", Map.get(csp, :connect_domains))
    map = maybe_put(map, "resourceDomains", Map.get(csp, :resource_domains))
    map = maybe_put(map, "frameDomains", Map.get(csp, :frame_domains))
    map = maybe_put(map, "baseUriDomains", Map.get(csp, :base_uri_domains))

    if map == %{}, do: nil, else: map
  end

  defp encode_permissions(nil), do: nil

  defp encode_permissions(permissions) when is_map(permissions) do
    map = %{}

    map = maybe_put(map, "camera", Map.get(permissions, :camera))
    map = maybe_put(map, "microphone", Map.get(permissions, :microphone))
    map = maybe_put(map, "geolocation", Map.get(permissions, :geolocation))
    map = maybe_put(map, "clipboardWrite", Map.get(permissions, :clipboard_write))

    if map == %{}, do: nil, else: map
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
