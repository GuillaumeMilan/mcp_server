# Building MCP Apps

This guide covers how to use `mcp_server` to build **MCP Apps** — interactive UIs delivered through sandboxed iframes alongside AI conversations. MCP Apps follow the [SEP-1865 specification](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx) (`io.modelcontextprotocol/ui` extension).

The library provides **server-side** support for declaring UI tools and resources, returning structured content, and generating Content Security Policies.

## Overview

MCP Apps extend the standard MCP protocol with two key concepts:

- **UI Resources** — HTML content served via `ui://` URIs with `text/html;profile=mcp-app` MIME type, rendered in sandboxed iframes
- **Structured Content** — Rich data returned alongside standard text content, optimized for UI rendering and excluded from model context

---

## Server-Side: Declaring UI Tools & Resources

### Linking Tools to UI Resources

Use the `ui` and `visibility` options on the `tool` macro to associate a tool with a UI resource:

```elixir
defmodule MyApp.Router do
  use McpServer.Router

  tool "get_weather", "Gets weather data", MyApp.WeatherController, :get_weather,
    ui: "ui://weather-server/dashboard",
    visibility: [:model, :app] do
    input_field("location", "Location", :string, required: true)
  end
end
```

**Options:**

- `ui` — URI of the UI resource that renders this tool's results. Must match a declared `ui://` resource.
- `visibility` — Controls who can access the tool (list of `McpServer.Tool.Meta.UI.visibility()` atoms):
  - `[:model, :app]` (default when `ui` is set) — Visible to both the AI model and the view
  - `[:app]` — Only callable from within a view (hidden from the model by the host)
  - `[:model]` — Only visible to the model

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
  app_domain "a904794854a047f6.example.com"

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

## PostMessage Lifecycle

MCP Apps communicate between the host and the iframe app using `window.postMessage()` with JSON-RPC 2.0 messages. There are two key lifecycle flows. The **initialization handshake** is initiated by the app — it sends a `ui/initialize` request, the host responds with capabilities and context, and the app confirms with `ui/notifications/initialized`. The host must not push any data until this handshake completes.

The **tool execution & interactive phase** begins when the host streams tool arguments via `ui/notifications/tool-input-partial` and `ui/notifications/tool-input`,
then delivers the result with `ui/notifications/tool-result` (or `ui/notifications/tool-cancelled`).
Once the app has data, it can call server tools (`tools/call`), send messages to the chat (`ui/message`),
update model context, request display mode changes, and more. For a complete deep-dive with sequence diagrams, message formats, and a step-by-step walkthrough, see [`MCP_APPS_LIFECYCLE_FRONTEND.md`](MCP_APPS_LIFECYCLE_FRONTEND.md).

---

## Content Security Policy

---

## Complete Example

A weather dashboard MCP App with server-side UI support:

### Router

```elixir
defmodule WeatherApp.Router do
  use McpServer.Router

  tool "get_weather", "Gets current weather", WeatherApp.Controller, :get_weather,
    ui: "ui://weather/dashboard",
    visibility: [:model, :app] do
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
       scheme: :http}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

---

## See Also

- `McpServer.Router` — DSL for defining tools, prompts, and resources
- `STRUCTURES.md` — Data structure reference for all App types
- [MCP Apps Specification](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx)
