# MCP Server Data Structures Documentation

This document describes all the data structures needed to support JSON encoding for the Model Context Protocol (MCP) server callbacks defined in `McpServer` behaviour.

## Overview

The MCP server requires structured data for four main capabilities:
1. **Tools** - Callable functions with input/output validation
2. **Prompts** - Interactive message templates with argument completion
3. **Resources** - Data sources with URI-based access
4. **Apps** - Interactive UI rendering via sandboxed iframes (MCP Apps extension)

All structures must be JSON-encodable (using `Jason` library) and follow the MCP protocol specification.

---

## 1. Tool-Related Structures

### 1.1 Tool Definition Structure

**Purpose**: Represents a complete tool definition with metadata and schema  
**Used by**: `list_tools/1` callback  
**JSON Field**: Top-level in tools list

```elixir
%McpServer.Tool{
  name: String.t(),           # Unique tool identifier
  description: String.t(),    # Human-readable description
  inputSchema: map(),         # JSON Schema for input validation
  annotations: map()          # Optional metadata (hints, title)
}
```

**JSON Example**:
```json
{
  "name": "calculator",
  "description": "Performs arithmetic operations",
  "inputSchema": {
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "description": "Operation to perform",
        "enum": ["add", "subtract", "multiply", "divide"]
      },
      "a": {
        "type": "number",
        "description": "First operand"
      },
      "b": {
        "type": "number",
        "description": "Second operand"
      }
    },
    "required": ["operation", "a", "b"]
  },
  "annotations": {
    "title": "Calculator",
    "readOnlyHint": true,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  }
}
```

### 1.2 Tool Annotations Structure

**Purpose**: Behavioral hints for tools  
**Used by**: `list_tools/1` callback (nested in Tool)  
**Fields**:

```elixir
%McpServer.Tool.Annotations{
  title: String.t() | nil,              # Display title
  readOnlyHint: boolean(),              # Doesn't modify state
  destructiveHint: boolean(),           # May have side effects
  idempotentHint: boolean(),            # Same result on repeated calls
  openWorldHint: boolean()              # Works with unbounded data
}
```

### 1.3 Input/Output Schema Structure

**Purpose**: JSON Schema for validating tool parameters  
**Used by**: `list_tools/1` callback (nested in Tool)  
**Format**: Standard JSON Schema object

```elixir
%McpServer.Schema{
  type: String.t(),                     # "object", "string", "number", etc.
  properties: map(),                    # Field definitions
  required: list(String.t()),           # Required field names
  # Optional fields for nested schemas:
  description: String.t() | nil,
  enum: list() | nil,
  default: any() | nil
}
```

### 1.4 Tool Call Result Structure

**Purpose**: Response from tool execution
**Used by**: `call_tool/3` callback return value
**Return Format**: `{:ok, content_list}` or `{:ok, %CallResult{}}` or `{:error, message}`

```elixir
# Standard response — list of content items
{:ok, [McpServer.Tool.Content.text("Result text")]}

# Extended response with structured content (MCP Apps)
{:ok, McpServer.Tool.CallResult.new(
  content: [McpServer.Tool.Content.text("Result text")],
  structured_content: %{"key" => "value"},
  _meta: %{"timestamp" => "2024-01-01"}
)}

# Error response
{:error, "Error message"}
```

### 1.5 Tool Call Result (Extended) — `McpServer.Tool.CallResult`

**Purpose**: Extended tool result supporting structured content for UI rendering
**Used by**: `call_tool/3` callback return value (MCP Apps)
**Module**: `McpServer.Tool.CallResult`

```elixir
%McpServer.Tool.CallResult{
  content: list(),                 # Standard content for model context (required)
  structured_content: map() | nil, # Structured data for UI rendering (excluded from model context)
  _meta: map() | nil               # Additional metadata (timestamps, source info)
}
```

**JSON Example**:
```json
{
  "content": [{"type": "text", "text": "Weather in NYC: 72F"}],
  "structuredContent": {
    "temperature": 72,
    "unit": "fahrenheit",
    "condition": "Sunny"
  },
  "_meta": {"source": "weather-api"},
  "isError": false
}
```

**Note**: `structuredContent` and `_meta` are omitted from the JSON response when `nil`.

---

## 2. Prompt-Related Structures

### 2.1 Prompt Definition Structure

**Purpose**: Represents a prompt template definition  
**Used by**: `prompts_list/1` (Router-generated function)  
**JSON Field**: Top-level in prompts list

```elixir
%McpServer.Prompt{
  name: String.t(),              # Unique prompt identifier
  description: String.t(),       # Human-readable description
  arguments: list(map())         # List of argument definitions
}
```

**JSON Example**:
```json
{
  "name": "code_review",
  "description": "Generates a code review prompt",
  "arguments": [
    {
      "name": "language",
      "description": "Programming language",
      "required": true
    },
    {
      "name": "code",
      "description": "Code to review",
      "required": true
    }
  ]
}
```

### 2.2 Prompt Argument Structure

**Purpose**: Defines an argument for a prompt  
**Used by**: Nested in Prompt Definition  

```elixir
%McpServer.Prompt.Argument{
  name: String.t(),              # Argument identifier
  description: String.t(),       # Human-readable description
  required: boolean()            # Whether argument is mandatory
}
```

### 2.3 Prompt Message Structure

**Purpose**: Represents a single message in a prompt response  
**Used by**: `get_prompt/3` callback return value  
**Helper**: `McpServer.Controller.message/3`

```elixir
%McpServer.Prompt.Message{
  role: String.t(),              # "user", "assistant", or "system"
  content: map()                 # Content object with type and text
}
```

**JSON Example**:
```json
{
  "role": "user",
  "content": {
    "type": "text",
    "text": "Hello world!"
  }
}
```

### 2.4 Message Content Structure

**Purpose**: Content of a prompt message  
**Used by**: Nested in Prompt Message  

```elixir
%McpServer.Prompt.MessageContent{
  type: String.t(),              # "text", "image", etc.
  text: String.t() | nil,        # For text type
  # ... extensible for other content types
}
```

### 2.5 Completion Result Structure

**Purpose**: Completion suggestions for prompt arguments  
**Used by**: `complete_prompt/3` callback return value  
**Helper**: `McpServer.Controller.completion/2`

```elixir
%McpServer.Completion{
  values: list(String.t()),      # Completion suggestions
  total: integer() | nil,        # Total available completions
  hasMore: boolean() | nil       # Whether more completions exist
}
```

**JSON Example**:
```json
{
  "values": ["Alice", "Bob", "Charlie"],
  "total": 10,
  "hasMore": true
}
```

---

## 3. Resource-Related Structures

### 3.1 Resource Definition Structure

**Purpose**: Represents a static resource  
**Used by**: `list_resources/1` callback  
**JSON Field**: Top-level in resources list

```elixir
%McpServer.Resource{
  name: String.t(),              # Unique resource identifier
  uri: String.t(),               # Static URI
  description: String.t() | nil, # Human-readable description
  mimeType: String.t() | nil,    # MIME type (e.g., "application/json")
  title: String.t() | nil        # Display title
}
```

**JSON Example**:
```json
{
  "name": "config",
  "uri": "file:///app/config.json",
  "description": "Application configuration file",
  "mimeType": "application/json",
  "title": "App Config"
}
```

### 3.2 Resource Template Structure

**Purpose**: Represents a templated resource with variables  
**Used by**: `list_templates_resource/1` (Router-generated function)  
**JSON Field**: Top-level in resource templates list

```elixir
%McpServer.ResourceTemplate{
  name: String.t(),              # Unique resource identifier
  uriTemplate: String.t(),       # URI with {variable} placeholders
  description: String.t() | nil, # Human-readable description
  mimeType: String.t() | nil,    # MIME type
  title: String.t() | nil        # Display title
}
```

**JSON Example**:
```json
{
  "name": "user",
  "uriTemplate": "https://api.example.com/users/{id}",
  "description": "User profile data",
  "mimeType": "application/json",
  "title": "User Profile"
}
```

### 3.3 Resource Read Result Structure

**Purpose**: Response from reading a resource  
**Used by**: `read_resource/3` callback return value  
**Helper**: `McpServer.Controller.content/3`

```elixir
%McpServer.Resource.ReadResult{
  contents: list(map())          # List of content items
}
```

**JSON Example**:
```json
{
  "contents": [
    {
      "name": "user_data.json",
      "uri": "https://api.example.com/users/123",
      "mimeType": "application/json",
      "text": "{\"id\": 123, \"name\": \"Alice\"}",
      "title": "User 123"
    }
  ]
}
```

### 3.4 Resource Content Structure

**Purpose**: Represents a single content item from a resource  
**Used by**: Nested in Resource Read Result  
**Helper**: `McpServer.Controller.content/3`

```elixir
%McpServer.Resource.Content{
  name: String.t(),              # Display name (e.g., filename)
  uri: String.t(),               # Canonical URI
  mimeType: String.t() | nil,    # MIME type
  text: String.t() | nil,        # Textual content
  blob: String.t() | nil,        # Base64-encoded binary content
  title: String.t() | nil        # Display title
}
```

**JSON Example (text content)**:
```json
{
  "name": "example.txt",
  "uri": "file:///path/to/example.txt",
  "mimeType": "text/plain",
  "text": "File content here...",
  "title": "Example File"
}
```

**JSON Example (binary content)**:
```json
{
  "name": "image.png",
  "uri": "file:///path/to/image.png",
  "mimeType": "image/png",
  "blob": "iVBORw0KGgoAAAANS..."
}
```

### 3.5 Resource Completion Result Structure

**Purpose**: Completion suggestions for resource URI template variables  
**Used by**: `complete_resource/3` callback return value  
**Format**: Same as Prompt Completion Result

```elixir
%McpServer.Completion{
  values: list(String.t()),      # Completion suggestions
  total: integer() | nil,        # Total available completions
  hasMore: boolean() | nil       # Whether more completions exist
}
```

---

## 4. MCP Apps Structures

These structures support the MCP Apps extension (`io.modelcontextprotocol/ui`).
For usage details, see [Building MCP Apps](MCP_APPS.md).

### 4.1 App Metadata Container — `McpServer.App.Meta`

**Purpose**: Wraps UI configuration for tools and resources in `_meta`
**Used by**: `list_tools/1`, `list_resources/1` responses
**Module**: `McpServer.App.Meta`

```elixir
%McpServer.App.Meta{
  ui: McpServer.App.UI.t() | McpServer.App.UIResourceMeta.t() | nil
}
```

**JSON Example**:
```json
{"ui": {"resourceUri": "ui://weather/dashboard", "visibility": ["model", "app"]}}
```

### 4.2 Tool UI Metadata — `McpServer.App.UI`

**Purpose**: Links tools to UI resources and controls visibility
**Used by**: Nested in `McpServer.App.Meta` on tools
**Module**: `McpServer.App.UI`

```elixir
%McpServer.App.UI{
  resource_uri: String.t() | nil,           # URI of the UI resource
  visibility: list(String.t())              # Default: ["model", "app"]
}
```

**JSON Example**:
```json
{"resourceUri": "ui://weather/dashboard", "visibility": ["model", "app"]}
```

### 4.3 Resource UI Metadata — `McpServer.App.UIResourceMeta`

**Purpose**: CSP, permissions, and sandbox settings for UI resources
**Used by**: Nested in `McpServer.App.Meta` on resources
**Module**: `McpServer.App.UIResourceMeta`

```elixir
%McpServer.App.UIResourceMeta{
  csp: %{
    connect_domains: list(String.t()),      # connect-src domains
    resource_domains: list(String.t()),     # script/style/img/font-src domains
    frame_domains: list(String.t()),        # frame-src domains
    base_uri_domains: list(String.t())      # base-uri domains
  } | nil,
  permissions: %{
    camera: map(),                          # Camera access
    microphone: map(),                      # Microphone access
    geolocation: map(),                     # Location access
    clipboard_write: map()                  # Clipboard write
  } | nil,
  domain: String.t() | nil,                # Dedicated sandbox origin
  prefers_border: boolean() | nil           # Visual boundary preference
}
```

**JSON Example**:
```json
{
  "csp": {
    "connectDomains": ["api.example.com"],
    "resourceDomains": ["cdn.example.com"]
  },
  "permissions": {"camera": {}, "clipboardWrite": {}},
  "domain": "a904794854a047f6.claudemcpcontent.com",
  "prefersBorder": true
}
```

---

## 5. Common Structures

### 5.1 Connection Context

**Purpose**: Provides session and request context to all callbacks  
**Not JSON-encoded**: Internal structure passed to all callbacks

```elixir
%McpServer.Conn{
  session_id: String.t(),        # Unique session identifier
  private: map()                 # Private storage for custom data
}
```

### 5.2 Error Response Structure

**Purpose**: Standard error format for all callbacks  
**Used by**: All callbacks can return error tuples

```elixir
{:error, String.t()}             # Simple error message
```

**Note**: For JSON-RPC errors, see `McpServer.JsonRpc.Error`

---

## 6. JSON-RPC Structures

### 6.1 JSON-RPC Request

**Purpose**: Incoming RPC request wrapper  
**Used by**: HTTP transport layer

```elixir
%McpServer.JsonRpc.Request{
  jsonrpc: "2.0",                # Protocol version
  method: String.t(),            # Method name (e.g., "tools/list")
  params: map() | list() | nil,  # Method parameters
  id: String.t() | integer() | nil  # Request ID
}
```

### 6.2 JSON-RPC Response

**Purpose**: Outgoing RPC response wrapper  
**Used by**: HTTP transport layer

```elixir
%McpServer.JsonRpc.Response{
  jsonrpc: "2.0",                # Protocol version
  result: any() | nil,           # Success result
  error: map() | nil,            # Error object
  id: String.t() | integer() | nil  # Request ID
}
```

### 6.3 JSON-RPC Error

**Purpose**: Standard error format for JSON-RPC  
**Used by**: Nested in JSON-RPC Response

```elixir
%McpServer.JsonRpc.Error{
  code: integer(),               # Error code
  message: String.t(),           # Error message
  data: any() | nil              # Additional error data
}
```

**Standard Error Codes**:
- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

---

## 7. Implementation Notes

### 7.1 JSON Encoding Protocol

All structures should implement the `Jason.Encoder` protocol for proper JSON serialization:

```elixir
defimpl Jason.Encoder, for: McpServer.Tool do
  def encode(value, opts) do
    Jason.Encode.map(%{
      "name" => value.name,
      "description" => value.description,
      "inputSchema" => value.inputSchema,
      "annotations" => value.annotations
    }, opts)
  end
end
```

### 7.2 Field Naming Conventions

- **Elixir structs**: Use `snake_case` for field names (e.g., `session_id`)
- **JSON output**: Use `camelCase` for field names (e.g., `"hasMore"`)
- **Exception**: Special cases like `inputSchema`, `uriTemplate` (as per MCP spec)

### 7.3 Optional Fields

Optional fields (marked with `| nil`) should be omitted from JSON if `nil`:

```elixir
# In encoder implementation
map
|> Map.reject(fn {_, v} -> is_nil(v) end)
|> Jason.Encode.map(opts)
```

### 7.4 Struct Modules Organization

Recommended module structure:

```
lib/mcp_server/
├── tool.ex               # Tool, Tool.Annotations
├── tool/
│   └── call_result.ex    # Tool.CallResult (MCP Apps)
├── prompt.ex             # Prompt, Prompt.Argument, Prompt.Message, Prompt.MessageContent
├── resource.ex           # Resource, ResourceTemplate, Resource.Content, Resource.ReadResult
├── completion.ex         # Completion (shared by prompts and resources)
├── schema.ex             # Schema (for JSON Schema validation)
├── json_rpc/
│   ├── request.ex
│   ├── response.ex
│   └── error.ex
└── app/                  # MCP Apps extension
    ├── meta.ex           # App.Meta (metadata container)
    ├── ui.ex             # App.UI (tool UI metadata)
    ├── ui_resource_meta.ex # App.UIResourceMeta (resource UI metadata)
    └── csp.ex            # App.CSP (Content Security Policy generation)
```

---

## 8. Validation Requirements

### 8.1 Tool Validation

- Tool names must be unique within a router
- Input/output field names must be unique within a tool
- Field types must be valid JSON Schema types
- Required fields must be properly declared

### 8.2 Prompt Validation

- Prompt names must be unique within a router
- Argument names must be unique within a prompt
- Get and complete functions must be defined
- Message roles must be "user", "assistant", or "system"

### 8.3 Resource Validation

- Resource names must be unique within a router
- URIs must be valid
- Template variables must match completion function expectations
- Read function must always be defined
- Complete function only for templated resources

---

## 9. Example Usage Patterns

### 9.1 Creating a Tool Definition

```elixir
tool = %McpServer.Tool{
  name: "echo",
  description: "Echoes back the input",
  inputSchema: %McpServer.Schema{
    type: "object",
    properties: %{
      "message" => %{
        "type" => "string",
        "description" => "Message to echo"
      }
    },
    required: ["message"]
  },
  annotations: %McpServer.Tool.Annotations{
    title: "Echo",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false
  }
}
```

### 9.2 Creating Prompt Messages

```elixir
messages = [
  %McpServer.Prompt.Message{
    role: "system",
    content: %McpServer.Prompt.MessageContent{
      type: "text",
      text: "You are a helpful assistant."
    }
  },
  %McpServer.Prompt.Message{
    role: "user",
    content: %McpServer.Prompt.MessageContent{
      type: "text",
      text: "Hello!"
    }
  }
]
```

### 9.3 Creating Resource Content

```elixir
content = %McpServer.Resource.Content{
  name: "config.json",
  uri: "file:///app/config.json",
  mimeType: "application/json",
  text: Jason.encode!(%{setting: "value"}),
  title: "Application Configuration"
}

read_result = %McpServer.Resource.ReadResult{
  contents: [content]
}
```

---

## 10. Migration Path

To implement these structures in the existing codebase:

1. **Phase 1**: Create struct definitions in new modules
2. **Phase 2**: Implement `Jason.Encoder` protocols
3. **Phase 3**: Update Router macro to use structs instead of maps
4. **Phase 4**: Update Controller helpers to return structs
5. **Phase 5**: Add tests for JSON encoding/decoding
6. **Phase 6**: Update documentation and examples

---

## 11. Summary Table

| Structure | Module | Purpose | Used By |
|-----------|--------|---------|---------|
| `Tool` | `McpServer.Tool` | Tool definition | `list_tools/1` |
| `Tool.Annotations` | `McpServer.Tool` | Tool metadata | Nested in Tool |
| `Schema` | `McpServer.Schema` | JSON Schema | Tool input/output |
| `Prompt` | `McpServer.Prompt` | Prompt definition | `prompts_list/1` |
| `Prompt.Argument` | `McpServer.Prompt` | Prompt argument | Nested in Prompt |
| `Prompt.Message` | `McpServer.Prompt` | Chat message | `get_prompt/3` |
| `Prompt.MessageContent` | `McpServer.Prompt` | Message content | Nested in Message |
| `Resource` | `McpServer.Resource` | Static resource | `list_resources/1` |
| `ResourceTemplate` | `McpServer.Resource` | Templated resource | `list_templates_resource/1` |
| `Resource.Content` | `McpServer.Resource` | Resource content | `read_resource/3` |
| `Resource.ReadResult` | `McpServer.Resource` | Read response | `read_resource/3` |
| `Completion` | `McpServer.Completion` | Completions | `complete_prompt/3`, `complete_resource/3` |
| `Conn` | `McpServer.Conn` | Connection context | All callbacks (exists) |
| `JsonRpc.Request` | `McpServer.JsonRpc` | RPC request | HTTP transport (exists) |
| `JsonRpc.Response` | `McpServer.JsonRpc` | RPC response | HTTP transport (exists) |
| `JsonRpc.Error` | `McpServer.JsonRpc` | RPC error | Nested in Response (exists) |
| `Tool.CallResult` | `McpServer.Tool.CallResult` | Extended tool result with structured content | `call_tool/3` (MCP Apps) |
| `App.Meta` | `McpServer.App.Meta` | Metadata container for UI config | `list_tools/1`, `list_resources/1` |
| `App.UI` | `McpServer.App.UI` | Tool UI metadata | Nested in Meta (tools) |
| `App.UIResourceMeta` | `McpServer.App.UIResourceMeta` | Resource UI metadata (CSP, permissions) | Nested in Meta (resources) |

---

This document provides a complete reference for all data structures needed to support the MCP server implementation with proper JSON encoding.
