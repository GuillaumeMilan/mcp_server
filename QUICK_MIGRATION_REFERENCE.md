# Quick Migration Reference Card

**Upgrading to MCP Server v0.4.0 - Struct-Based API**

## TL;DR - What You Need to Change

### 1. Router List Functions: Add conn Parameter

```elixir
# ❌ OLD (v0.3.x) - No arguments
tools = MyRouter.tools_list()
prompts = MyRouter.prompts_list()

# ✅ NEW (v0.4.0+) - Requires conn, returns tuple
{:ok, tools} = MyRouter.list_tools(conn)
{:ok, prompts} = MyRouter.prompts_list(conn)
```

### 2. Controller Functions: Add conn as First Parameter

```elixir
# ❌ OLD (v0.3.x) - Arity 1
def my_tool(args) do
  # ...
end

def read_resource(opts) do
  # ...
end

def complete("arg", prefix) do
  # ...
end

# ✅ NEW (v0.4.0+) - Arity 2 (or 3 for complete)
def my_tool(conn, args) do
  # Can now access conn.session_id
end

def read_resource(conn, opts) do
  # ...
end

def complete(conn, "arg", prefix) do
  # ...
end
```

### 3. Field Access: Maps → Structs

```elixir
# ❌ OLD (v0.3.x)
tool["name"]
prompt["description"]
resource["uri"]

# ✅ NEW (v0.4.0+)
tool.name
prompt.description
resource.uri
```

### 4. Return Values: Use Controller Helpers

```elixir
# ❌ OLD - Manual map construction
def read_file(opts) do
  %{
    "contents" => [
      %{
        "name" => "file.txt",
        "uri" => "file:///path",
        "mimeType" => "text/plain",
        "text" => "content"
      }
    ]
  }
end

# ✅ NEW - Use helper functions + conn parameter
def read_file(conn, opts) do
  McpServer.Resource.ReadResult.new(
    contents: [
      content("file.txt", "file:///path",
        mime_type: "text/plain",
        text: "content"
      )
    ]
  )
end
```

## Field Name Conversion (snake_case ↔ camelCase)

| In Elixir (snake_case) | In JSON (camelCase) |
|------------------------|---------------------|
| `.mime_type` | `"mimeType"` |
| `.uri_template` | `"uriTemplate"` |
| `.has_more` | `"hasMore"` |
| `.input_schema` | `"inputSchema"` |
| `.read_only_hint` | `"readOnlyHint"` |

**Rule:** Always use snake_case in Elixir. JSON encoder handles conversion automatically.

## Controller Helper Functions (Already Return Structs)

```elixir
import McpServer.Controller

# Returns McpServer.Resource.Content
content(name, uri, opts)

# Returns McpServer.Prompt.Message  
message(role, type, text)

# Returns McpServer.Completion
completion(values, opts)
```

## What Doesn't Change

✅ Router DSL syntax (`tool`, `prompt`, `resource`)  
✅ Controller function signatures  
✅ JSON API output format  
✅ HTTP transport layer

## Find & Replace Patterns

### Pattern 1: Basic Field Access
```
Find:    &1["name"]
Replace: &1.name

Find:    result["values"]
Replace: result.values

Find:    tool["description"]
Replace: tool.description
```

### Pattern 2: Map Access in Tests
```
Find:    assert.*\["(\w+)"\]
Replace: assert.*.\1
```

### Pattern 3: Nested Field Access
```
Find:    msg["content"]["text"]
Replace: msg.content.text

Find:    tool["inputSchema"]["type"]
Replace: tool.input_schema.type
```

## Common Struct Types

```elixir
%McpServer.Tool{name: _, description: _, input_schema: _, annotations: _}
%McpServer.Prompt{name: _, description: _, arguments: _}
%McpServer.Resource{name: _, uri: _, ...}
%McpServer.ResourceTemplate{name: _, uri_template: _, ...}
%McpServer.Completion{values: _, total: _, has_more: _}
%McpServer.Resource.Content{name: _, uri: _, mime_type: _, text: _, ...}
%McpServer.Resource.ReadResult{contents: _}
%McpServer.Prompt.Message{role: _, content: _}
```

## Quick Troubleshooting

### Error: `function fetch/2 is undefined`
**Fix:** Change `struct["field"]` → `struct.field`

### Error: `key :name not found`
**Fix:** Include all required fields when creating structs

### Error: Pattern match failed in tests
**Fix:** Update assertions from `["field"]` to `.field`

## Full Documentation

See [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for detailed migration instructions with complete examples.

## Estimated Migration Time

- **Small projects** (< 5 controllers): 10 minutes
- **Medium projects** (5-20 controllers): 20 minutes  
- **Large projects** (20+ controllers): 30 minutes

Most changes are simple find-and-replace operations! 🚀
