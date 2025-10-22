# Changelog Entry - v0.4.0

## [0.4.0] - 2025-10-21

### Major Release: Struct-Based API

This release introduces typed Elixir structs throughout the MCP server library, replacing the previous map-based approach. This provides better type safety, improved IDE support, and clearer error messages.

### ⚠️ Breaking Changes

#### Router List Functions Now Require conn Parameter and Return Structs

Router list functions have been renamed, now require a `conn` parameter, and return tuples with typed structs:

- `tools_list()` → `list_tools(conn)` returns `{:ok, [McpServer.Tool.t()]}`
- `prompts_list()` → `prompts_list(conn)` returns `{:ok, [McpServer.Prompt.t()]}`
- Resource listing functions now accept `conn` parameter

**Migration:** Add `conn` parameter, handle tuple return, change field access from `["field"]` to `.field`

```elixir
# Before (v0.3.x)
tools = MyRouter.tools_list()
tool_names = Enum.map(tools, & &1["name"])

# After (v0.4.0+)
{:ok, tools} = MyRouter.list_tools(conn)
tool_names = Enum.map(tools, & &1.name)
```

#### Controller Functions Now Require conn Parameter

ALL controller functions now require a `conn` parameter as their first argument:

- Tool functions: `def tool(args)` → `def tool(conn, args)` (arity 1 → 2)
- Prompt get functions: `def get(args)` → `def get(conn, args)` (arity 1 → 2)
- Prompt complete functions: `def complete(arg, prefix)` → `def complete(conn, arg, prefix)` (arity 2 → 3)
- Resource read functions: `def read(opts)` → `def read(conn, opts)` (arity 1 → 2)
- Resource complete functions: `def complete(arg, prefix)` → `def complete(conn, arg, prefix)` (arity 2 → 3)

**Migration:** Add `conn` as first parameter to ALL controller functions

```elixir
# Before (v0.3.x) - No conn parameter
def read_file(opts) do
  %{
    "contents" => [
      %{"name" => "file", "uri" => "...", "text" => "..."}
    ]
  }
end

# After (v0.4.0+) - With conn parameter + return struct
def read_file(conn, opts) do
  McpServer.Resource.ReadResult.new(
    contents: [
      content("file", "file:///path", text: "...")
    ]
  )
end
```

#### Controller Helpers Now Return Structs

The controller helper functions now return typed structs:

- `content/3` returns `McpServer.Resource.Content.t()`
- `message/3` returns `McpServer.Prompt.Message.t()`
- `completion/2` returns `McpServer.Completion.t()`

### New Features

#### Comprehensive Struct Types

Added 16 new struct types organized into 5 modules:

**Schema Module** (`McpServer.Schema`)
- `Schema` - JSON Schema validation for tool parameters

**Tool Module** (`McpServer.Tool`)
- `Tool` - Tool definition with metadata
- `Tool.Annotations` - Behavioral hints (read_only, idempotent, etc.)

**Completion Module** (`McpServer.Completion`)
- `Completion` - Completion suggestions for prompts and resources

**Prompt Module** (`McpServer.Prompt`)
- `Prompt` - Prompt template definition
- `Argument` - Prompt argument specification
- `Message` - Prompt message with role and content
- `MessageContent` - Structured message content (text, image, etc.)

**Resource Module** (`McpServer.Resource` and `McpServer.ResourceTemplate`)
- `Resource` - Static resource definition
- `ResourceTemplate` - Templated resource with URI variables
- `Content` - Resource content (text or binary blob)
- `ReadResult` - Resource read response wrapper

#### Helper Functions

All structs include `new/1` helper functions for easy construction:

```elixir
McpServer.Tool.new(
  name: "my_tool",
  description: "Does something useful",
  input_schema: schema,
  annotations: annotations
)
```

#### Automatic JSON Encoding

All structs implement the `Jason.Encoder` protocol with automatic field name conversion:

- Elixir: `snake_case` → JSON: `camelCase`
- `mime_type` → `"mimeType"`
- `uri_template` → `"uriTemplate"`
- `has_more` → `"hasMore"`
- `nil` fields automatically omitted from JSON

#### Compile-Time Validation

Structs use `@enforce_keys` to ensure required fields are provided at compile time:

```elixir
# Compile error if required fields missing
McpServer.Resource.new(uri: "file:///test")
# ** (KeyError) key :name not found
```

### 🔧 Improvements

- **Type Safety**: All return values now have proper type specifications (`@spec`)
- **IDE Support**: Better autocomplete and inline documentation
- **Error Messages**: Clearer errors when fields are missing or incorrect
- **Consistency**: Unified structure throughout the codebase
- **Documentation**: Comprehensive docs with examples for all structs

### 📚 Documentation

New documentation added:

- `STRUCTURES.md` - Complete documentation of all 16 structures
- `MIGRATION_GUIDE.md` - Step-by-step migration guide from v0.3.x
- `QUICK_MIGRATION_REFERENCE.md` - Quick reference card for migration
- `INTEGRATION_SUMMARY.md` - Technical implementation details
- `ROUTER_UPDATE_SUMMARY.md` - Router changes documentation

### Backward Compatibility

While this is a breaking change in the API, the following remain unchanged:

- Router DSL syntax (`tool`, `prompt`, `resource` macros)
- Controller function signatures (still `(conn, args)`)
- JSON API output format (same structure)
- HTTP transport layer (no changes required)
- Validation logic and error handling

### Migration Path

Estimated migration time: **10-30 minutes** for most projects

1. Update field access: `["field"]` → `.field`
2. Use controller helpers (already return structs)
3. Update test assertions
4. Verify JSON output (should be identical)

See [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for detailed instructions.

### Bug Fixes

- Fixed inconsistent field naming between maps and JSON
- Fixed missing field validation in controller responses
- Fixed optional field handling (now properly omits `nil` values)

### Internal Changes

- Router macro now generates structs instead of maps
- Eliminated post-processing transformations for resources
- Simplified conditional map building throughout codebase
- Improved code generation in `__before_compile__` macro

### Notes

This release represents a significant architectural improvement to the MCP server library. While it requires some migration effort, the benefits in type safety, developer experience, and code clarity make it worthwhile.

For questions or issues during migration, please:
1. Review the [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)
2. Check existing tests for examples
3. Open an issue on GitHub if you need help

---

**Full Changelog**: v0.3.0...v0.4.0
