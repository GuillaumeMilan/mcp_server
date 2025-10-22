# Migration Guide: Upgrading to Struct-Based API

This guide will help you migrate your MCP server from the map-based API to the new struct-based API introduced in version 0.4.0.

## Overview

Starting with version 0.4.0, the MCP server library uses typed Elixir structs instead of plain maps for all MCP protocol structures. This provides better type safety, improved IDE support, and clearer error messages.

**Good news:** Most of your code will continue to work without changes! The Router DSL and controller function signatures remain the same.

## Breaking Changes Summary

### What Changed

1. **Router list functions** now return structs instead of maps
2. **Controller helper functions** now return structs instead of maps
3. **Field access** requires using struct notation (`.field`) instead of map notation (`["field"]`)

### What Hasn't Changed

- Router DSL syntax (`tool`, `prompt`, `resource` macros) - exactly the same
- JSON output format - identical structure, same camelCase field names
- HTTP transport layer - no changes needed
- Validation logic - same rules
- Error handling patterns - same approach

The core DSL you learned remains the same - you're just getting better types and needing to thread `conn` through your controllers!

## Migration Steps

### 1. Update Router List Function Usage

Router list functions now require a `conn` parameter AND return structs instead of plain maps.

#### Before (v0.3.x - No conn, Map Access)
```elixir
tools = MyRouter.tools_list()
tool_names = Enum.map(tools, & &1["name"])
first_tool = List.first(tools)
IO.puts("Tool: #{first_tool["name"]} - #{first_tool["description"]}")
```

#### After (v0.4.0+ - With conn, Struct Access)
```elixir
{:ok, tools} = MyRouter.list_tools(conn)
tool_names = Enum.map(tools, & &1.name)
first_tool = List.first(tools)
IO.puts("Tool: #{first_tool.name} - #{first_tool.description}")
```

**Changes Required:**
1. Function name: `tools_list()` → `list_tools(conn)`
2. Function name: `prompts_list()` → `prompts_list(conn)`
3. Add `conn` parameter to all list function calls
4. Handle `{:ok, results}` tuple return value
5. Replace all `["field_name"]` with `.field_name` for field access

### 2. Update Controller Function Signatures

Controller functions now receive a `conn` parameter as the first argument.

#### Before (v0.3.x - Arity 1, Return Maps)
```elixir
defmodule MyApp.Tools do
  def my_tool(args) do
    # No conn parameter available
    name = args["name"]
    "Hello, #{name}!"
  end
end

defmodule MyApp.Resources do
  import McpServer.Controller

  def read_config(_opts) do
    %{
      "contents" => [
        content("config.json", "file:///config.json",
          text: Jason.encode!(%{setting: "value"}),
          mimeType: "application/json"
        )
      ]
    }
  end
end
```

#### After (v0.4.0+ - Arity 2, Return Structs)
```elixir
defmodule MyApp.Tools do
  def my_tool(conn, args) do
    # conn parameter now available for session info
    IO.inspect(conn.session_id)
    name = args["name"]
    "Hello, #{name}!"
  end
end

defmodule MyApp.Resources do
  import McpServer.Controller

  def read_config(conn, _opts) do
    # Can access conn.session_id, conn.private, etc.
    McpServer.Resource.ReadResult.new(
      contents: [
        content("config.json", "file:///config.json",
          text: Jason.encode!(%{setting: "value"}),
          mimeType: "application/json"
        )
      ]
    )
  end
end
```

**Changes Required:**
1. Add `conn` as first parameter to ALL controller functions
2. Tool functions: `def my_tool(args)` → `def my_tool(conn, args)`
3. Prompt get functions: `def get_prompt(args)` → `def get_prompt(conn, args)`
4. Prompt complete functions: `def complete(arg, prefix)` → `def complete(conn, arg, prefix)`
5. Resource read functions: `def read(opts)` → `def read(conn, opts)`
6. Resource complete functions: `def complete(arg, prefix)` → `def complete(conn, arg, prefix)`
7. Return `ReadResult` struct for resource read handlers
8. Use struct field access (`.field`) instead of map access (`["field"]`)

### 3. Update Test Assertions

If you have tests that verify Router or controller output, update the assertions.

#### Before (Map Assertions)
```elixir
test "lists tools" do
  {:ok, tools} = MyRouter.list_tools(conn)
  
  assert length(tools) == 3
  assert Enum.any?(tools, & &1["name"] == "my_tool")
  
  tool = Enum.find(tools, & &1["name"] == "my_tool")
  assert tool["description"] == "My tool description"
  assert tool["inputSchema"]["type"] == "object"
end

test "creates completion" do
  result = completion(["foo", "bar"], total: 10, has_more: true)
  
  assert result["values"] == ["foo", "bar"]
  assert result["total"] == 10
  assert result["hasMore"] == true
end
```

#### After (Struct Assertions)
```elixir
test "lists tools" do
  {:ok, tools} = MyRouter.list_tools(conn)
  
  assert length(tools) == 3
  assert Enum.any?(tools, & &1.name == "my_tool")
  
  tool = Enum.find(tools, & &1.name == "my_tool")
  assert %McpServer.Tool{} = tool
  assert tool.description == "My tool description"
  assert tool.input_schema.type == "object"
end

test "creates completion" do
  result = completion(["foo", "bar"], total: 10, has_more: true)
  
  assert %McpServer.Completion{} = result
  assert result.values == ["foo", "bar"]
  assert result.total == 10
  assert result.has_more == true
  
  # Verify JSON encoding still works
  json = Jason.encode!(result)
  decoded = Jason.decode!(json)
  assert decoded["hasMore"] == true  # camelCase in JSON
end
```

## Quick Reference: Struct Types

### Tools
```elixir
%McpServer.Tool{
  name: String.t(),
  description: String.t(),
  input_schema: McpServer.Schema.t(),
  annotations: McpServer.Tool.Annotations.t()
}
```

### Prompts
```elixir
%McpServer.Prompt{
  name: String.t(),
  description: String.t(),
  arguments: [McpServer.Prompt.Argument.t()]
}
```

### Resources (Static)
```elixir
%McpServer.Resource{
  name: String.t(),
  uri: String.t(),
  description: String.t() | nil,
  mime_type: String.t() | nil,
  title: String.t() | nil
}
```

### Resources (Templated)
```elixir
%McpServer.ResourceTemplate{
  name: String.t(),
  uri_template: String.t(),
  description: String.t() | nil,
  mime_type: String.t() | nil,
  title: String.t() | nil
}
```

### Content
```elixir
%McpServer.Resource.Content{
  name: String.t(),
  uri: String.t(),
  mime_type: String.t() | nil,
  text: String.t() | nil,
  blob: String.t() | nil,
  title: String.t() | nil
}
```

### Messages
```elixir
%McpServer.Prompt.Message{
  role: String.t(),
  content: McpServer.Prompt.MessageContent.t()
}
```

### Completion
```elixir
%McpServer.Completion{
  values: [String.t()],
  total: integer() | nil,
  has_more: boolean() | nil
}
```

### Schema
```elixir
%McpServer.Schema{
  type: String.t(),
  properties: map() | nil,
  required: [String.t()] | nil,
  description: String.t() | nil,
  enum: [any()] | nil,
  default: any() | nil
}
```

## Field Name Mapping: Struct vs JSON

When working with structs, remember that field names use `snake_case` in Elixir but are automatically converted to `camelCase` in JSON:

| Struct Field (Elixir) | JSON Field |
|----------------------|------------|
| `mime_type` | `mimeType` |
| `uri_template` | `uriTemplate` |
| `has_more` | `hasMore` |
| `read_only_hint` | `readOnlyHint` |
| `destructive_hint` | `destructiveHint` |
| `idempotent_hint` | `idempotentHint` |
| `open_world_hint` | `openWorldHint` |
| `input_schema` | `inputSchema` |

**Important:** Always use `snake_case` when working with structs in Elixir code. The JSON encoder handles the conversion automatically.

## Common Migration Patterns

### Pattern 1: Iterating Over Lists

```elixir
# Before (v0.3.x) - No conn, map access
tools = MyRouter.tools_list()
Enum.each(tools, fn tool ->
  IO.puts("#{tool["name"]}: #{tool["description"]}")
end)

# After (v0.4.0+) - With conn, struct access
{:ok, tools} = MyRouter.list_tools(conn)
Enum.each(tools, fn tool ->
  IO.puts("#{tool.name}: #{tool.description}")
end)
```

### Pattern 2: Controller Functions with conn

```elixir
# Before (v0.3.x) - Arity 1, no conn
defmodule MyApp.Tools do
  def greet(args) do
    name = args["name"]
    "Hello, #{name}!"
  end
end

# After (v0.4.0+) - Arity 2, with conn
defmodule MyApp.Tools do
  def greet(conn, args) do
    # Can now access session info
    IO.inspect(conn.session_id)
    name = args["name"]
    "Hello, #{name}!"
  end
end
```

### Pattern 3: Building Resource Responses

```elixir
# Before (v0.3.x) - No conn, return map with string keys
def read_file(%{"path" => path}) do
  file_content = File.read!(path)
  
  %{
    "contents" => [
      %{
        "name" => Path.basename(path),
        "uri" => "file://#{path}",
        "mimeType" => "text/plain",
        "text" => file_content
      }
    ]
  }
end

# After (v0.4.0+) - With conn, return ReadResult struct
def read_file(conn, %{"path" => path}) do
  file_content = File.read!(path)
  
  McpServer.Resource.ReadResult.new(
    contents: [
      content(
        Path.basename(path),
        "file://#{path}",
        mime_type: "text/plain",
        text: file_content
      )
    ]
  )
end
```

### Pattern 4: Creating Completions

```elixir
# Before (v0.3.x) - Arity 2, return map
def complete_language("lang", prefix) do
  languages = ["elixir", "erlang", "javascript"]
  filtered = Enum.filter(languages, &String.starts_with?(&1, prefix))
  
  %{
    "values" => filtered,
    "total" => length(languages),
    "hasMore" => false
  }
end

# After (v0.4.0+) - Arity 3 with conn, return struct
def complete_language(conn, "lang", prefix) do
  languages = ["elixir", "erlang", "javascript"]
  filtered = Enum.filter(languages, &String.starts_with?(&1, prefix))
  
  completion(filtered, total: length(languages), has_more: false)
end
```

## Troubleshooting

### Error: `function fetch/2 is undefined`

**Problem:**
```elixir
** (UndefinedFunctionError) function McpServer.Tool.fetch/2 is undefined 
(McpServer.Tool does not implement the Access behaviour)
```

**Solution:** You're trying to access a struct with map syntax. Change `struct["field"]` to `struct.field`.

```elixir
# Wrong
tool["name"]

# Correct
tool.name
```

### Error: `key :name not found`

**Problem:**
```elixir
** (KeyError) key :name not found in: [description: "...", uri: "..."]
```

**Solution:** You're missing a required field when creating a struct. Check the struct definition for `@enforce_keys`.

```elixir
# Wrong - missing required :name field
McpServer.Resource.new(uri: "file:///test", description: "Test")

# Correct - includes all required fields
McpServer.Resource.new(name: "test", uri: "file:///test", description: "Test")
```

### Error: Pattern match failed

**Problem:**
```elixir
# Test fails: pattern match (=) failed
assert result["values"] == ["foo", "bar"]
```

**Solution:** Update assertions to use struct field access.

```elixir
# Correct
assert result.values == ["foo", "bar"]
```

## Benefits of the New API

### 1. Better Type Safety
```elixir
# Compiler catches typos
tool.descripption  # Compile error: unknown field
tool.description   # Works!
```

### 2. Better IDE Support
Your IDE can now provide autocomplete and inline documentation for all fields.

### 3. Clearer Error Messages
```elixir
# Before (map)
%{name: "test"}  # Silently accepts any fields

# After (struct)
McpServer.Tool.new(name: "test")
# ** (KeyError) key :description not found
# Clear error showing what's missing!
```

### 4. Guaranteed Field Names
```elixir
# Before (map) - typos create bugs
%{"mimeType" => "text/plain"}  # Oops! Should be "mimeType" or "mime_type"?

# After (struct) - typos cause compile errors
content(..., mime_type: "text/plain")  # Compiler validates field name
```

## Need Help?

If you encounter issues during migration:

1. Check the [STRUCTURES.md](./STRUCTURES.md) document for detailed struct definitions
2. Review the [INTEGRATION_SUMMARY.md](./INTEGRATION_SUMMARY.md) for implementation details
3. Look at the test files in `test/mcp_server/` for usage examples
4. Open an issue on GitHub if you find a bug or need assistance

## Version Compatibility

- **Version 0.3.x and earlier**: Map-based API
- **Version 0.4.0 and later**: Struct-based API (this guide)

If you need to support both versions, you can use pattern matching:

```elixir
def process_tool(tool) do
  case tool do
    %McpServer.Tool{name: name, description: desc} ->
      # Version 0.4.0+ (struct)
      {name, desc}
    
    %{"name" => name, "description" => desc} ->
      # Version 0.3.x (map)
      {name, desc}
  end
end
```

## Summary

The migration requires a few systematic changes:

1. **Add `conn` parameter** to ALL controller functions (first parameter)
2. **Update Router function calls**: `tools_list()` → `list_tools(conn)` and handle tuple returns
3. **Replace `["field"]` with `.field`** for accessing returned values  
4. **Use helper functions** (`content/3`, `message/3`, `completion/2`) for return values
5. **Wrap resource responses** in `ReadResult.new()`
6. **Update tests** to use struct assertions
