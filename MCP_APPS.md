# Building MCP Apps

This guide covers how to use `mcp_server` to build **MCP Apps** — interactive UIs delivered through sandboxed iframes alongside AI conversations. MCP Apps follow the [SEP-1865 specification](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx) (`io.modelcontextprotocol/ui` extension).

The library provides both **server-side** support (declaring UI tools and resources) and **host-side** support (managing view lifecycles via the `McpServer.App.Host` behaviour and `McpServer.App.HostPlug`).

## Overview

MCP Apps extend the standard MCP protocol with two key concepts:

- **UI Resources** — HTML content served via `ui://` URIs with `text/html;profile=mcp-app` MIME type, rendered in sandboxed iframes
- **Structured Content** — Rich data returned alongside standard text content, optimized for UI rendering and excluded from model context

There are two roles:

| Role | Responsibility |
|------|---------------|
| **Server** | Declares tools with UI metadata, serves UI resources, returns structured content |
| **Host** | Manages iframe lifecycle, proxies tool calls, handles view requests (open links, messages, display modes) |

---

## Server-Side: Declaring UI Tools & Resources

### Linking Tools to UI Resources

Use the `ui` and `visibility` options on the `tool` macro to associate a tool with a UI resource:

```elixir
defmodule MyApp.Router do
  use McpServer.Router

  tool "get_weather", "Gets weather data", MyApp.WeatherController, :get_weather,
    ui: "ui://weather-server/dashboard",
    visibility: ["model", "app"] do
    input_field("location", "Location", :string, required: true)
  end
end
```

**Options:**

- `ui` — URI of the UI resource that renders this tool's results. Must match a declared `ui://` resource.
- `visibility` — Controls who can access the tool:
  - `["model", "app"]` (default when `ui` is set) — Visible to both the AI model and the view
  - `["app"]` — Only callable from within a view (hidden from the model by the host)
  - `["model"]` — Only visible to the model

### Declaring UI Resources

UI resources use the `ui://` scheme and serve HTML content that runs inside sandboxed iframes. Declare them with the standard `resource` macro, adding CSP and permission metadata inside the block:

```elixir
resource "dashboard", "ui://weather-server/dashboard" do
  description "Interactive weather dashboard"
  mimeType "text/html;profile=mcp-app"
  read MyApp.WeatherController, :read_dashboard

  # Content Security Policy — which external domains are allowed
  csp connect_domains: ["api.weather.com", "ws.weather.com"],
      resource_domains: ["cdn.weather.com"],
      frame_domains: ["maps.google.com"],
      base_uri_domains: ["weather-server.example.com"]

  # Sandbox permissions the app needs
  permissions camera: true, microphone: true, geolocation: true, clipboard_write: true

  # Dedicated sandbox origin domain (assigned by host)
  app_domain "a904794854a047f6.claudemcpcontent.com"

  # Whether the host should draw a visual boundary around the iframe
  prefers_border true
end
```

**CSP fields** map to Content-Security-Policy directives:

| Field | CSP Directive |
|-------|--------------|
| `connect_domains` | `connect-src` (API calls, WebSockets) |
| `resource_domains` | `script-src`, `style-src`, `img-src`, `media-src`, `font-src` |
| `frame_domains` | `frame-src` |
| `base_uri_domains` | `base-uri` |

When no CSP is declared, a restrictive default is applied (no network access, inline scripts only).

**Permission fields** request sandbox capabilities:

| Field | Permission |
|-------|-----------|
| `camera` | Camera access |
| `microphone` | Microphone access |
| `geolocation` | Location access |
| `clipboard_write` | Clipboard write access |


### Returning Structured Content

Controllers can return `McpServer.Tool.CallResult` to include structured data optimized for UI rendering alongside standard text content:

```elixir
defmodule MyApp.WeatherController do
  alias McpServer.Tool.Content
  alias McpServer.Tool.CallResult

  def get_weather(_conn, %{"location" => location}) do
    weather = fetch_weather(location)

    {:ok,
     CallResult.new(
       content: [Content.text("Weather in #{location}: #{weather.temp}F, #{weather.condition}")],
       structured_content: %{
         "temperature" => weather.temp,
         "unit" => "fahrenheit",
         "condition" => weather.condition,
         "forecast" => weather.forecast
       },
       _meta: %{"source" => "weather-api", "fetched_at" => DateTime.utc_now()}
     )}
  end
end
```

**Fields:**

| Field | Purpose | In model context? |
|-------|---------|-------------------|
| `content` | Text representation for the AI model (required) | Yes |
| `structured_content` | Rich data for UI rendering | No |
| `_meta` | Additional metadata (timestamps, source info) | No |

**Backward compatibility:** Controllers returning a plain content list `{:ok, [content_items]}` continue to work. The `structuredContent` field is simply omitted from the response.

### Extension Negotiation

The server automatically advertises the `io.modelcontextprotocol/ui` extension during `initialize`:

```json
{
  "capabilities": {
    "tools": {"listChanged": true},
    "resources": {"listChanged": true},
    "extensions": {
      "io.modelcontextprotocol/ui": {
        "mimeTypes": ["text/html;profile=mcp-app"]
      }
    }
  }
}
```

Client capabilities sent in the `initialize` request are stored in the session ETS table for later use.

---

## Host-Side: Implementing a Host

The host manages iframe lifecycles and proxies communication between views and MCP servers. The library provides data types, a behaviour, and a Plug for building hosts.

### Data Types

Three structs define the host-view handshake:

**`McpServer.App.HostCapabilities`** — What the host supports:

```elixir
HostCapabilities.new(
  open_links: %{},                      # Host can open external URLs
  server_tools: %{list_changed: true},  # Host proxies tool calls
  server_resources: %{list_changed: false},
  logging: %{},                         # Host accepts log messages
  sandbox: %{permissions: %{camera: %{}}}
)
```

**`McpServer.App.HostContext`** — Environment information for the view:

```elixir
HostContext.new(
  theme: "dark",
  display_mode: "inline",
  available_display_modes: ["inline", "fullscreen", "pip"],
  locale: "en-US",
  time_zone: "America/New_York",
  platform: "desktop",
  device_capabilities: %{touch: false, hover: true},
  container_dimensions: %{width: 600, max_height: 400}
)
```

**`McpServer.App.AppCapabilities`** — What the view declares:

```elixir
AppCapabilities.new(
  tools: %{list_changed: true},
  available_display_modes: ["inline", "fullscreen"]
)
```

All three structs serialize to JSON with camelCase keys and omit nil fields.

### Implementing the Host Behaviour

Implement `McpServer.App.Host` to handle view requests:

```elixir
defmodule MyApp.HostHandler do
  @behaviour McpServer.App.Host

  alias McpServer.App.{HostCapabilities, HostContext}

  @impl true
  def handle_initialize(_host_conn, _app_capabilities) do
    host_caps = HostCapabilities.new(
      open_links: %{},
      server_tools: %{list_changed: false},
      logging: %{}
    )

    host_ctx = HostContext.new(
      theme: "dark",
      display_mode: "inline",
      available_display_modes: ["inline", "fullscreen"],
      locale: "en-US"
    )

    {:ok, %{host_capabilities: host_caps, host_context: host_ctx}}
  end

  @impl true
  def handle_open_link(_host_conn, url) do
    System.cmd("open", [url])
    :ok
  end

  @impl true
  def handle_message(_host_conn, role, content) do
    IO.inspect({role, content}, label: "View message")
    :ok
  end

  @impl true
  def handle_request_display_mode(_host_conn, mode) do
    {:ok, mode}
  end

  @impl true
  def handle_update_model_context(_host_conn, _content, _structured_content) do
    :ok
  end

  @impl true
  def handle_size_changed(_host_conn, _width, _height) do
    :ok
  end

  @impl true
  def handle_teardown_response(_host_conn) do
    :ok
  end
end
```

**Callbacks:**

| Callback | Required? | Purpose |
|----------|-----------|---------|
| `handle_initialize/2` | Yes | Returns host capabilities and context |
| `handle_open_link/2` | No | Opens an external URL |
| `handle_message/3` | No | Adds a message to the conversation |
| `handle_request_display_mode/2` | No | Changes the display mode |
| `handle_update_model_context/3` | No | Updates model context from the view |
| `handle_size_changed/3` | No | Handles iframe size changes |
| `handle_teardown_response/1` | No | Acknowledges view teardown |

### Mounting HostPlug

`McpServer.App.HostPlug` is a Plug that handles JSON-RPC messages from views:

```elixir
# In your application supervision tree
children = [
  {Bandit,
   plug: {McpServer.App.HostPlug,
          host: MyApp.HostHandler,
          router: MyApp.Router,
          server_info: %{name: "MyApp", version: "1.0.0"}},
   port: 4001}
]
```

**Options:**

| Option | Required? | Description |
|--------|-----------|-------------|
| `host` | Yes | Module implementing `McpServer.App.Host` |
| `router` | Yes | Module using `McpServer.Router` (for proxying `tools/call` and `resources/read`) |
| `server_info` | No | Server metadata map (defaults to `%{}`) |
| `init` | No | Function `(Plug.Conn.t() -> map())` to build host connection context |

The plug handles these methods from views:

| Method | Action |
|--------|--------|
| `ui/initialize` | Delegates to `handle_initialize/2` |
| `ui/open-link` | Delegates to `handle_open_link/2` |
| `ui/message` | Delegates to `handle_message/3` |
| `ui/request-display-mode` | Delegates to `handle_request_display_mode/2` |
| `ui/update-model-context` | Delegates to `handle_update_model_context/3` |
| `ui/notifications/size-changed` | Delegates to `handle_size_changed/3` |
| `ui/resource-teardown` | Delegates to `handle_teardown_response/1` |
| `tools/call` | Proxied to `router.call_tool/3` |
| `resources/read` | Proxied to `router.read_resource/3` |
| `ping` | Returns empty result |

### Sending Notifications to Views

Use the `McpServer.App.HostPlug` helper functions to build notification messages for sending to views through your transport layer (WebSocket, postMessage relay, etc.):

```elixir
alias McpServer.App.HostPlug

# Send tool arguments to the view
msg = HostPlug.notify_tool_input(%{"location" => "NYC", "unit" => "fahrenheit"})

# Stream partial tool arguments
msg = HostPlug.notify_tool_input_partial(%{"location" => "NY"})

# Send tool execution result
msg = HostPlug.notify_tool_result(%{
  "content" => [%{"type" => "text", "text" => "72F"}],
  "isError" => false
})

# Notify that tool execution was cancelled
msg = HostPlug.notify_tool_cancelled("user_request")

# Notify the view that host context changed (e.g., theme switch)
msg = HostPlug.notify_host_context_changed(%{"theme" => "light"})

# Request the view to tear down
request = HostPlug.notify_resource_teardown("navigation", 42)
```

Each helper returns a JSON-RPC notification map (or request struct for teardown) that you serialize with `Jason.encode!/1` and send through your transport.

---

## Content Security Policy

The `McpServer.App.CSP` module generates Content-Security-Policy headers from `UIResourceMeta` configuration:

```elixir
alias McpServer.App.{CSP, UIResourceMeta}

# Restrictive default (no network access)
CSP.generate(nil)
# => "default-src 'none'; script-src 'self' 'unsafe-inline'; ..."

# Custom CSP from resource metadata
meta = UIResourceMeta.new(
  csp: %{
    connect_domains: ["api.example.com"],
    resource_domains: ["cdn.example.com"]
  }
)
CSP.generate(meta)
# => "default-src 'none'; script-src 'self' 'unsafe-inline' cdn.example.com; ..."
```

Use this when building the iframe sandbox on the host side to set the `Content-Security-Policy` header.

---

## JSON-RPC Message Helpers

The `McpServer.App.Messages` module provides encode/decode functions for all `ui/*` JSON-RPC messages. These are used internally by `HostPlug` but can also be used directly for custom host implementations:

```elixir
alias McpServer.App.Messages

# Encode a ui/initialize response
response = Messages.encode_initialize_response(host_caps, host_ctx, request_id)

# Decode a ui/open-link request
{:ok, url} = Messages.decode_open_link(params)

# Encode a tool-input notification
notification = Messages.encode_tool_input(%{"location" => "NYC"})

# Decode a size-changed notification
{:ok, %{width: 800, height: 600}} = Messages.decode_size_changed(params)
```

---

## Complete Example

A weather dashboard MCP App with both server and host sides:

### Router

```elixir
defmodule WeatherApp.Router do
  use McpServer.Router

  tool "get_weather", "Gets current weather", WeatherApp.Controller, :get_weather,
    ui: "ui://weather/dashboard",
    visibility: ["model", "app"] do
    input_field("location", "City name", :string, required: true)
  end

  resource "dashboard", "ui://weather/dashboard" do
    description "Interactive weather dashboard"
    mimeType "text/html;profile=mcp-app"
    read WeatherApp.Controller, :read_dashboard

    csp connect_domains: ["api.openweathermap.org"]
    prefers_border true
  end
end
```

### Controller

```elixir
defmodule WeatherApp.Controller do
  alias McpServer.Tool.{Content, CallResult}
  import McpServer.Controller, only: [content: 3]

  def get_weather(_conn, %{"location" => location}) do
    weather = fetch_from_api(location)

    {:ok,
     CallResult.new(
       content: [Content.text("#{location}: #{weather.temp}F, #{weather.condition}")],
       structured_content: %{
         "location" => location,
         "temperature" => weather.temp,
         "condition" => weather.condition,
         "humidity" => weather.humidity,
         "forecast" => weather.five_day
       }
     )}
  end

  def read_dashboard(_conn, _params) do
    html = File.read!("priv/dashboard.html")

    McpServer.Resource.ReadResult.new(
      contents: [
        content("Weather Dashboard", "ui://weather/dashboard",
          mimeType: "text/html;profile=mcp-app",
          text: html
        )
      ]
    )
  end
end
```

### Host

```elixir
defmodule WeatherApp.Host do
  @behaviour McpServer.App.Host
  alias McpServer.App.{HostCapabilities, HostContext}

  @impl true
  def handle_initialize(_host_conn, _app_caps) do
    {:ok, %{
      host_capabilities: HostCapabilities.new(
        open_links: %{},
        server_tools: %{list_changed: false}
      ),
      host_context: HostContext.new(
        theme: "dark",
        display_mode: "inline",
        available_display_modes: ["inline", "fullscreen"],
        locale: "en-US"
      )
    }}
  end

  @impl true
  def handle_open_link(_host_conn, url) do
    System.cmd("open", [url])
    :ok
  end
end
```

### Application Setup

```elixir
defmodule WeatherApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # MCP server endpoint (for AI clients)
      {Bandit,
       plug: {McpServer.HttpPlug,
              router: WeatherApp.Router,
              server_info: %{name: "WeatherApp", version: "1.0.0"}},
       port: 4000,
       scheme: :http},

      # Host endpoint (for view iframes)
      {Bandit,
       plug: {McpServer.App.HostPlug,
              host: WeatherApp.Host,
              router: WeatherApp.Router},
       port: 4001,
       scheme: :http}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

---

## See Also

- `McpServer.Router` — DSL for defining tools, prompts, and resources
- `McpServer.App.Host` — Host behaviour callbacks
- `McpServer.App.HostPlug` — Plug for host-view communication
- `McpServer.App.Messages` — JSON-RPC message helpers
- `McpServer.App.CSP` — Content Security Policy generation
- `STRUCTURES.md` — Data structure reference for all App types
- [MCP Apps Specification](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx)
