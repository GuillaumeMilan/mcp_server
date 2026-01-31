# MCP Apps PostMessage Lifecycle

This document is a deep-dive into the two postMessage lifecycle flows used by MCP Apps: the **initialization handshake** and the **tool execution & interactive phase**. It covers the transport layer, sequence diagrams, the complete JSON-RPC method reference, and a step-by-step developer walkthrough.

For the broader MCP Apps guide (declaring tools, resources, CSP, host behaviour), see [`MCP_APPS.md`](MCP_APPS.md).

---

## 1. Transport Layer

MCP Apps communicate between the **host** (the application embedding the iframe) and the **app** (the HTML/JS running inside the iframe) using [`window.postMessage()`](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage).

- Messages are **JSON-RPC 2.0** objects serialized as JSON strings.
- The **app** sends messages to the host via `window.parent.postMessage(message, "*")`.
- The **host** sends messages to the app via `iframe.contentWindow.postMessage(message, targetOrigin)`.
- There is no HTTP or WebSocket connection between the host and the app — `postMessage` is the sole channel.

On the host side, `McpServer.App.HostPlug` is an HTTP Plug that relays JSON-RPC messages received from a frontend bridge (which itself listens for `postMessage` events from the iframe and forwards them over HTTP). The notification helpers on `HostPlug` produce JSON-RPC maps that the frontend bridge sends back to the iframe via `postMessage`.

For the iframe side, the `@modelcontextprotocol/ext-apps` npm package provides a `PostMessageTransport` that wraps `postMessage` into an MCP SDK-compatible transport. This library also ships a lightweight, dependency-free `McpApp` class at `priv/js/mcp_app.js.eex`. Embed it in your HTML template with `McpServer.JS.mcp_app_script/1`.

---

## 2. Lifecycle 1 — Initialization Handshake

The initialization handshake establishes capabilities and context between host and app. The **app initiates** the handshake — the host waits for the iframe to be ready.

```
Host                                        App (iframe)
  |                                            |
  |--- creates iframe, loads HTML ------------>|
  |                                            |
  |                                            |-- App JS boots
  |                                            |-- creates PostMessageTransport (or McpApp)
  |                                            |-- sends ui/initialize request -->
  |<-- postMessage({jsonrpc:"2.0",             |   {protocolVersion, appCapabilities}
  |     method:"ui/initialize", ...}) ---------|
  |                                            |
  |-- host.handle_initialize()                 |
  |-- validates app capabilities               |
  |-- sends ui/initialize response ----------->|   {hostCapabilities, hostContext}
  |                                            |
  |                                            |-- receives response
  |                                            |-- stores hostCapabilities + hostContext
  |                                            |-- sends ui/notifications/initialized -->
  |<-- postMessage({method:                    |
  |     "ui/notifications/initialized"}) ------|
  |                                            |
  |-- bridge.oninitialized fires               |
  |-- Host is now free to send notifications   |
```

### Key points

- The **app** initiates — it sends `ui/initialize` as a JSON-RPC **request** (has an `id`).
- The **host** responds with `hostCapabilities` (what the host supports) and `hostContext` (theme, locale, display mode, etc.).
- After receiving the response, the app sends `ui/notifications/initialized` as a JSON-RPC **notification** (no `id`).
- The host must not send any notifications to the app until it receives `ui/notifications/initialized`.

### Messages involved

| Step | Method | Direction | Type | Payload |
|------|--------|-----------|------|---------|
| 1 | `ui/initialize` | App → Host | Request | `{appCapabilities: {tools?, availableDisplayModes?, experimental?}}` |
| 2 | `ui/initialize` | Host → App | Response | `{hostCapabilities: {...}, hostContext: {...}}` |
| 3 | `ui/notifications/initialized` | App → Host | Notification | `{}` |

### JavaScript: initiating handshake

Using the lightweight helper:

```javascript
const app = new McpApp();
const { hostCapabilities, hostContext } = await app.connect();
// hostContext.theme => "dark"
// hostCapabilities.openLinks => {}
```

---

## 3. Lifecycle 2 — Tool Execution & Interactive Phase

After initialization, the host pushes tool data to the app via notifications, and the app can make requests back to the host.

```
Host/Agent                                  App (iframe)
  |                                            |
  | [LLM generates tool args (streaming)]      |
  |-- ui/notifications/tool-input-partial ---->|  (partial args as they stream)
  |-- ui/notifications/tool-input-partial ---->|
  |-- ui/notifications/tool-input ------------>|  (complete args)
  |                                            |
  | [Host calls MCP server tools/call]         |
  |                                            |
  |-- ui/notifications/tool-result ----------->|  (execution result)
  |                                            |
  | [OR if cancelled]                          |
  |-- ui/notifications/tool-cancelled -------->|  (reason)
  |                                            |
  | --- Interactive phase ---                  |
  |                                            |
  |<-- tools/call (request) -------------------|  App calls server tool
  |-- tools/call (response) ----------------->|  Fresh data back
  |                                            |
  |<-- ui/message -----------------------------|  App adds msg to chat
  |<-- ui/update-model-context ----------------|  App updates model context
  |<-- ui/open-link ---------------------------|  App requests URL open
  |<-- ui/request-display-mode ----------------|  App requests fullscreen/pip
  |<-- ui/notifications/size-changed ----------|  App reports resize
  |                                            |
  |-- ui/notifications/host-context-changed -->|  Theme/locale change
  |                                            |
  | --- Teardown ---                           |
  |-- ui/resource-teardown (request) --------->|
  |<-- ui/resource-teardown (response) --------|
```

### Tool data flow

1. **Streaming partial args** — As the LLM generates tool arguments, the host sends `ui/notifications/tool-input-partial` with the partial JSON so the app can render a preview.
2. **Complete args** — Once arguments are finalized, the host sends `ui/notifications/tool-input`.
3. **Tool result** — After executing the tool via `tools/call` on the MCP server, the host sends `ui/notifications/tool-result` with the full result (content, structured content, error status).
4. **Cancellation** — If the tool call is cancelled, the host sends `ui/notifications/tool-cancelled` instead.

### Interactive requests (app → host)

Once the app has data, it can interact with the host:

| Method | Purpose | Response |
|--------|---------|----------|
| `tools/call` | Call a server tool to fetch fresh data | Tool result |
| `ui/message` | Add a message to the conversation | `{}` |
| `ui/update-model-context` | Update what the model sees in future turns | `{}` |
| `ui/open-link` | Ask the host to open a URL | `{}` |
| `ui/request-display-mode` | Request fullscreen, pip, or inline | `{mode: actualMode}` |

### Host-initiated notifications

| Method | Purpose |
|--------|---------|
| `ui/notifications/host-context-changed` | Theme, locale, or display mode changed |
| `ui/resource-teardown` | Host is about to destroy the iframe |

### JavaScript: handling tool data

```javascript
const app = new McpApp();

app.ontoolinputpartial = (args) => {
  renderPreview(args);
};

app.ontoolinput = (args) => {
  renderFinal(args);
};

app.ontoolresult = (result) => {
  renderResult(result);
};

app.ontoolcancelled = (reason) => {
  showCancellation(reason);
};

await app.connect();
```

### JavaScript: making interactive requests

```javascript
// Call a server tool
const result = await app.callServerTool("get_forecast", { location: "NYC", days: 5 });

// Add a message to the conversation
await app.sendMessage("assistant", { type: "text", text: "Weather updated!" });

// Update what the model sees
await app.updateModelContext(
  [{ type: "text", text: "Current temp: 72°F" }],
  { temperature: 72, unit: "fahrenheit" }
);

// Open a link in the host browser
await app.openLink("https://weather.com/nyc");

// Request fullscreen
const { mode } = await app.requestDisplayMode("fullscreen");
```

---

## 4. Complete JSON-RPC Method Reference

### App → Host (requests)

| Method | Type | Params | Response |
|--------|------|--------|----------|
| `ui/initialize` | Request | `{appCapabilities: AppCapabilities}` | `{hostCapabilities: HostCapabilities, hostContext: HostContext}` |
| `ui/open-link` | Request | `{url: string}` | `{}` |
| `ui/message` | Request | `{role: string, content: object}` | `{}` |
| `ui/request-display-mode` | Request | `{mode: string}` | `{mode: string}` |
| `ui/update-model-context` | Request | `{content?: array, structuredContent?: object}` | `{}` |
| `tools/call` | Request | `{name: string, arguments: object}` | Tool result |
| `resources/read` | Request | `{uri: string}` | Resource contents |
| `ping` | Request | `{}` | `{}` |

### App → Host (notifications)

| Method | Type | Params |
|--------|------|--------|
| `ui/notifications/initialized` | Notification | `{}` |
| `ui/notifications/size-changed` | Notification | `{width: number, height: number}` |

### Host → App (notifications)

| Method | Type | Params |
|--------|------|--------|
| `ui/notifications/tool-input` | Notification | `{arguments: object}` |
| `ui/notifications/tool-input-partial` | Notification | `{arguments: object}` |
| `ui/notifications/tool-result` | Notification | Tool result object |
| `ui/notifications/tool-cancelled` | Notification | `{reason: string}` |
| `ui/notifications/host-context-changed` | Notification | Partial `HostContext` |

### Host → App (requests)

| Method | Type | Params | Response |
|--------|------|--------|----------|
| `ui/resource-teardown` | Request | `{reason: string}` | `{}` |

### Type definitions

**AppCapabilities:**
```json
{
  "experimental": {},
  "tools": { "listChanged": true },
  "availableDisplayModes": ["inline", "fullscreen"]
}
```

**HostCapabilities:**
```json
{
  "experimental": {},
  "openLinks": {},
  "serverTools": { "listChanged": true },
  "serverResources": { "listChanged": false },
  "logging": {},
  "sandbox": {}
}
```

**HostContext:**
```json
{
  "toolInfo": {},
  "theme": "dark",
  "styles": {},
  "displayMode": "inline",
  "availableDisplayModes": ["inline", "fullscreen", "pip"],
  "containerDimensions": { "width": 600, "maxHeight": 400 },
  "locale": "en-US",
  "timeZone": "America/New_York",
  "userAgent": "MyHost/1.0",
  "platform": "desktop",
  "deviceCapabilities": { "touch": false, "hover": true },
  "safeAreaInsets": { "top": 0, "right": 0, "bottom": 0, "left": 0 }
}
```

**Tool result (ui/notifications/tool-result params):**
```json
{
  "content": [
    { "type": "text", "text": "72°F, Sunny" },
    { "type": "image", "data": "base64...", "mimeType": "image/png" }
  ],
  "isError": false,
  "structuredContent": { "temp": 72, "condition": "Sunny" }
}
```

---

## 5. Developer Walkthrough

This section walks through a complete implementation of both sides using `mcp_server` and the `McpApp` JS helper.

### Step 1: Define the MCP server (Elixir)

```elixir
defmodule MyApp.Router do
  use McpServer.Router

  tool "analyze_data", "Analyzes uploaded data", MyApp.DataController, :analyze,
    ui: "ui://myapp/dashboard",
    visibility: ["model", "app"] do
    input_field("dataset", "Dataset name", :string, required: true)
  end

  resource "dashboard", "ui://myapp/dashboard" do
    description "Interactive data dashboard"
    mimeType "text/html;profile=mcp-app"
    read MyApp.DataController, :read_dashboard
    csp connect_domains: ["api.myapp.com"]
  end
end
```

### Step 2: Mount the plug (Elixir)

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # MCP server endpoint (for AI clients)
      {Bandit,
       plug: {McpServer.HttpPlug,
              router: MyApp.Router,
              server_info: %{name: "MyApp", version: "1.0.0"}},
       port: 4000}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Step 3: Write the app HTML + JS (iframe side)

For this phase we recommend using the lightweight `McpApp` helper at `priv/js/mcp_app.js.eex` and embedding it directly into your HTML.
For this you can use library such as EEx to create the HTML template.

Here is an example `dashboard.html.eex`:
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Data Dashboard</title>
  <script><%= McpServer.JS.mcp_app_script() %></script>
</head>
<body>
  <div id="status">Connecting...</div>
  <div id="preview" hidden></div>
  <div id="result" hidden></div>
  <button id="refresh" hidden>Refresh Data</button>

  <script>
    const app = new McpApp();

    // Handle streaming preview
    app.ontoolinputpartial = (args) => {
      document.getElementById("preview").hidden = false;
      document.getElementById("preview").textContent =
        "Preparing: " + JSON.stringify(args);
    };

    // Handle complete input
    app.ontoolinput = (args) => {
      document.getElementById("preview").textContent =
        "Analyzing: " + args.dataset;
    };

    // Handle tool result
    app.ontoolresult = (result) => {
      document.getElementById("result").hidden = false;
      if (result.structuredContent) {
        renderChart(result.structuredContent);
      } else {
        document.getElementById("result").textContent =
          result.content.map(c => c.text).join("\n");
      }
      document.getElementById("refresh").hidden = false;
    };

    // Handle cancellation
    app.ontoolcancelled = (reason) => {
      document.getElementById("status").textContent =
        "Cancelled: " + reason;
    };

    // Handle host context changes (e.g., theme switch)
    app.onhostcontextchanged = (ctx) => {
      if (ctx.theme) {
        document.body.className = ctx.theme;
      }
    };

    // Handle teardown
    app.onteardown = async (reason) => {
      // Clean up resources before iframe is destroyed
      cleanup();
    };

    // Connect and update status
    app.connect().then(({ hostContext }) => {
      document.getElementById("status").textContent = "Connected";
      document.body.className = hostContext.theme || "light";
    });

    // Interactive: refresh data by calling a server tool
    document.getElementById("refresh").addEventListener("click", async () => {
      const result = await app.callServerTool("analyze_data", {
        dataset: "latest"
      });
      renderChart(result.structuredContent || result);
    });

    function renderChart(data) {
      document.getElementById("result").textContent =
        JSON.stringify(data, null, 2);
    }

    function cleanup() {
      // Release resources
    }
  </script>
</body>
</html>
```

## See Also

- [`MCP_APPS.md`](MCP_APPS.md) — Main MCP Apps guide
- `McpServer.App.Messages` — JSON-RPC message encode/decode helpers
- `McpServer.App.Lifecycle` — Lifecycle orchestration helpers
- `McpServer.JS.mcp_app_script/1` — Embed the `McpApp` JS class in your HTML templates
- [MCP Apps Specification (SEP-1865)](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx)
