defmodule McpServer.App.HostCapabilities do
  @moduledoc """
  Represents the capabilities of an MCP Apps host.

  Sent to the view during `ui/initialize` to inform it of what the host supports.

  ## Fields

  - `experimental` - Experimental features (structure TBD)
  - `open_links` - Set to `%{}` if host supports opening external URLs
  - `server_tools` - Tool proxy capabilities (`%{list_changed: boolean()}`)
  - `server_resources` - Resource proxy capabilities (`%{list_changed: boolean()}`)
  - `logging` - Set to `%{}` if host accepts log messages
  - `sandbox` - Sandbox configuration applied by the host
  """

  defstruct [
    :experimental,
    :open_links,
    :server_tools,
    :server_resources,
    :logging,
    :sandbox
  ]

  @type t :: %__MODULE__{
          experimental: map() | nil,
          open_links: map() | nil,
          server_tools: map() | nil,
          server_resources: map() | nil,
          logging: map() | nil,
          sandbox: map() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      experimental: Keyword.get(opts, :experimental),
      open_links: Keyword.get(opts, :open_links),
      server_tools: Keyword.get(opts, :server_tools),
      server_resources: Keyword.get(opts, :server_resources),
      logging: Keyword.get(opts, :logging),
      sandbox: Keyword.get(opts, :sandbox)
    }
  end
end

defmodule McpServer.App.HostContext do
  @moduledoc """
  Represents the context provided by a host to a view during initialization.

  Contains information about the current display state, theme, locale,
  and the tool call that instantiated the view.

  ## Fields

  - `tool_info` - Metadata of the tool call that instantiated the view
  - `theme` - Current color theme (`"light"` or `"dark"`)
  - `styles` - Style configuration for theming
  - `display_mode` - Current display mode (`"inline"`, `"fullscreen"`, `"pip"`)
  - `available_display_modes` - Display modes the host supports
  - `container_dimensions` - Container dimensions for the iframe
  - `locale` - User's language/region preference (BCP 47, e.g., `"en-US"`)
  - `time_zone` - User's timezone (IANA, e.g., `"America/New_York"`)
  - `user_agent` - Host application identifier
  - `platform` - Platform type (`"web"`, `"desktop"`, `"mobile"`)
  - `device_capabilities` - Device capabilities (`%{touch: boolean(), hover: boolean()}`)
  - `safe_area_insets` - Safe area boundaries in pixels
  """

  defstruct [
    :tool_info,
    :theme,
    :styles,
    :display_mode,
    :available_display_modes,
    :container_dimensions,
    :locale,
    :time_zone,
    :user_agent,
    :platform,
    :device_capabilities,
    :safe_area_insets
  ]

  @type t :: %__MODULE__{
          tool_info: map() | nil,
          theme: String.t() | nil,
          styles: map() | nil,
          display_mode: String.t() | nil,
          available_display_modes: list(String.t()) | nil,
          container_dimensions: map() | nil,
          locale: String.t() | nil,
          time_zone: String.t() | nil,
          user_agent: String.t() | nil,
          platform: String.t() | nil,
          device_capabilities: map() | nil,
          safe_area_insets: map() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      tool_info: Keyword.get(opts, :tool_info),
      theme: Keyword.get(opts, :theme),
      styles: Keyword.get(opts, :styles),
      display_mode: Keyword.get(opts, :display_mode),
      available_display_modes: Keyword.get(opts, :available_display_modes),
      container_dimensions: Keyword.get(opts, :container_dimensions),
      locale: Keyword.get(opts, :locale),
      time_zone: Keyword.get(opts, :time_zone),
      user_agent: Keyword.get(opts, :user_agent),
      platform: Keyword.get(opts, :platform),
      device_capabilities: Keyword.get(opts, :device_capabilities),
      safe_area_insets: Keyword.get(opts, :safe_area_insets)
    }
  end
end

defmodule McpServer.App.AppCapabilities do
  @moduledoc """
  Represents the capabilities declared by a view (app) during `ui/initialize`.

  ## Fields

  - `experimental` - Experimental features (structure TBD)
  - `tools` - App exposes MCP-style tools that the host can call
  - `available_display_modes` - Display modes the app supports
  """

  defstruct [
    :experimental,
    :tools,
    :available_display_modes
  ]

  @type t :: %__MODULE__{
          experimental: map() | nil,
          tools: map() | nil,
          available_display_modes: list(String.t()) | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      experimental: Keyword.get(opts, :experimental),
      tools: Keyword.get(opts, :tools),
      available_display_modes: Keyword.get(opts, :available_display_modes)
    }
  end
end

# Jason Encoders

defimpl Jason.Encoder, for: McpServer.App.HostCapabilities do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "experimental", value.experimental)
    map = maybe_put(map, "openLinks", value.open_links)
    map = maybe_put(map, "serverTools", encode_capability(value.server_tools))
    map = maybe_put(map, "serverResources", encode_capability(value.server_resources))
    map = maybe_put(map, "logging", value.logging)
    map = maybe_put(map, "sandbox", encode_sandbox(value.sandbox))

    Jason.Encode.map(map, opts)
  end

  defp encode_capability(nil), do: nil

  defp encode_capability(cap) when is_map(cap) do
    map = %{}
    map = maybe_put(map, "listChanged", Map.get(cap, :list_changed))
    if map == %{}, do: cap, else: map
  end

  defp encode_sandbox(nil), do: nil
  defp encode_sandbox(sandbox) when is_map(sandbox), do: sandbox

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.App.HostContext do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "toolInfo", encode_tool_info(value.tool_info))
    map = maybe_put(map, "theme", value.theme)
    map = maybe_put(map, "styles", value.styles)
    map = maybe_put(map, "displayMode", value.display_mode)
    map = maybe_put(map, "availableDisplayModes", value.available_display_modes)
    map = maybe_put(map, "containerDimensions", value.container_dimensions)
    map = maybe_put(map, "locale", value.locale)
    map = maybe_put(map, "timeZone", value.time_zone)
    map = maybe_put(map, "userAgent", value.user_agent)
    map = maybe_put(map, "platform", value.platform)
    map = maybe_put(map, "deviceCapabilities", value.device_capabilities)
    map = maybe_put(map, "safeAreaInsets", encode_insets(value.safe_area_insets))

    Jason.Encode.map(map, opts)
  end

  defp encode_tool_info(nil), do: nil
  defp encode_tool_info(info) when is_map(info), do: info

  defp encode_insets(nil), do: nil
  defp encode_insets(insets) when is_map(insets), do: insets

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: McpServer.App.AppCapabilities do
  def encode(value, opts) do
    map = %{}

    map = maybe_put(map, "experimental", value.experimental)
    map = maybe_put(map, "tools", encode_tools(value.tools))
    map = maybe_put(map, "availableDisplayModes", value.available_display_modes)

    Jason.Encode.map(map, opts)
  end

  defp encode_tools(nil), do: nil

  defp encode_tools(tools) when is_map(tools) do
    map = %{}
    map = maybe_put(map, "listChanged", Map.get(tools, :list_changed))
    if map == %{}, do: tools, else: map
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
