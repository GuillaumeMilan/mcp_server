# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-02-01

### MCP Apps Support

Implements the [SEP-1865](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/draft/apps.mdx) specification for interactive UIs delivered through sandboxed iframes alongside AI conversations.

### Added

- **Tool & Resource metadata** — `Meta` and `Meta.UI` structs for both tools and resources
- **UI resources** — `ui://` URI scheme with `text/html;profile=mcp-app` MIME type
- **Tool visibility** — `:model`, `:app`, or both, controlling who can invoke a tool
- **Structured content** — `Tool.CallResult` for returning rich data alongside text
- **CSP & permissions** — `Resource.Meta.UI.CSP` and `Resource.Meta.UI.Permissions` for iframe sandboxing
- **Router DSL extensions** — `ui:` and `visibility:` options on `tool`, new `resource` macro for UI resources
- **JS bridge** — EEx template (`priv/js/mcp_app.js.eex`) for frontend ↔ server communication

## [0.7.0] - 2026-01-29

### Major Feature: Tool Content Helpers & Result Validation

This release introduces convenience helper functions for building tool results
and adds runtime validation for tool return values.

### Breaking Changes

- **Tool functions must return `{:ok, result}` or `{:error, reason}`**: Bare return values
  (e.g., returning a plain string or integer) now raise an error instead of being silently
  wrapped in `{:ok, result}`. Wrap your return values explicitly.

### What's New

- **Tool Content Helper Functions** (`McpServer.Tool.Content`):
  - `text/1` - Create text content items
  - `image/2` - Create image content items (binary data + MIME type)
  - `resource/2` - Create embedded resource content items (URI + options)
  - These replace the lower-level struct constructors with a cleaner API

- **Tool Result Validation** (`McpServer.Router`):
  - `validate_tool_result/2` checks that tool functions return a list of valid content items
  - Emits `Logger.warning/1` when tools return invalid formats (strings, integers, maps, etc.)
  - Warnings include tool name, expected types, and index of invalid items
  - Results still pass through unchanged for backward compatibility

### Deprecated

- `McpServer.Controller.text_content/1` — use `McpServer.Tool.Content.text/1` instead
- `McpServer.Controller.image_content/2` — use `McpServer.Tool.Content.image/2` instead
- `McpServer.Controller.resource_content/2` — use `McpServer.Tool.Content.resource/2` instead

### Bug Fixes

- **HTTP session initialization**: Moved `init_conn_callback` from the request body handler
  to SSE stream initialization, ensuring the MCP connection is created with the correct
  session ID context

### Documentation

- Added "Controller Implementation" section to README with examples for all content types
- Updated all README examples to use `McpServer.Tool.Content` helpers
- Updated Router module documentation with content type usage examples

## [0.6.0] - 2025-12-03

### Major Feature: Recursive Schema Definitions & Tool Callbacks

This release implements the MCP specification for recursive schema definitions and adds internal callback tracking to tools.

### What's New

- **Recursive Schema Support**: Schemas can now contain nested schemas as properties or array items, fully matching the MCP specification
  - `ArraySchema`: Arrays with items that can be any schema type
  - Arbitrary nesting depth for objects and arrays
  - All primitive types can be nested: StringSchema, NumberSchema, BooleanSchema, ObjectSchema, ArraySchema

- **Tool Callback Information**: Tools now track their controller callback internally
  - `{module, function}` tuple stored in `Tool.callback` field
  - Automatically populated from router DSL definitions
  - Not serialized to JSON (internal use only)
  - Useful for runtime introspection and tool execution

### Improvements

- **Schema Module** (`McpServer.Schema`):
  - Added `:items` field for array schema definitions
  - Updated type definition for true recursion: `items: t() | nil`
  - Improved documentation with recursive schema examples
  - Enhanced encoder to handle nested Schema structs properly

- **Router Functions**:
  - `format_schema/1`: Now returns Schema struct directly instead of maps
  - `format_field/1`: Refactored to return Schema structs with recursive handling
  - `list_tools/1`: Automatically captures and stores callback information

- **Tool Structure** (`McpServer.Tool`):
  - Added `:callback` field to store controller information
  - Updated `new/1` to accept optional `:callback` parameter
  - Complete type information: `callback_info :: {module :: atom(), function :: atom()} | nil`

### Code Examples

**Recursive Object Schema:**

```elixir
address_schema =
  Schema.new(
    type: "object",
    properties: %{
      "street" => Schema.new(type: "string"),
      "city" => Schema.new(type: "string"),
      "zip" => Schema.new(type: "string")
    },
    required: ["city"]
  )

user_schema =
  Schema.new(
    type: "object",
    properties: %{
      "name" => Schema.new(type: "string"),
      "address" => address_schema
    },
    required: ["name"]
  )
```

**Array with Nested Objects:**

```elixir
items_schema =
  Schema.new(
    type: "object",
    properties: %{
      "id" => Schema.new(type: "integer"),
      "name" => Schema.new(type: "string")
    },
    required: ["id"]
  )

array_schema =
  Schema.new(
    type: "array",
    items: items_schema
  )
```

**Tool with Callback Tracking:**

```elixir
tool = Tool.new(
  name: "calculate",
  description: "Performs calculations",
  input_schema: schema,
  callback: {MathController, :calculate}
)

# Access callback at runtime
{module, function} = tool.callback
# Use for introspection or dynamic invocation
```

### Bug Fixes

- Schema encoder now properly handles nested Schema structs in properties and items
- Router schema generation returns typed Schema structs instead of maps
- All recursive schema patterns now fully compliant with MCP specification

### Quality Assurance

- Added 6 new unit tests for callback functionality
- Added 3 new integration tests for router callback population
- Updated existing schema tests for recursive definitions
- Updated router tests to handle Schema struct field access
- All 186 tests passing (180 existing + 6 new)

### Compatibility

- **100% backward compatible**: Existing code continues to work without modification
- **Optional callback field**: Callbacks are optional, can be `nil`
- **No breaking changes**: Schema API extends existing functionality
- **Automatic population**: Router DSL automatically sets callbacks, no user action needed

### Upgrade Guide

If you're using `McpServer.Schema.new/1`:

- You can now optionally pass `items: schema` for array definitions
- Properties can now be Schema structs (maps still work for compatibility)
- No changes required if you're using the router DSL

If you want to access tool callbacks:

```elixir
# Get the controller and function for a tool
{controller, function} = tool.callback

# Use for runtime introspection
if tool.callback do
  {module, func} = tool.callback
  # Do something with the callback
end
```

## [0.5.0] - 2025-11-13

### Major Feature: Nested Structure Support

This release adds comprehensive support for deeply nested objects and arrays in the Router DSL, allowing you to define complex, hierarchical data schemas for tool inputs and outputs.

### Added

- **Block-based DSL for nested structures**: Define nested object properties and array items using intuitive do-blocks
- **New `field/3-5` macro**: Use inside `input_field` or `output_field` do-blocks to define nested properties
- **New `items/1-3` macro**: Define array item schemas (both simple types and complex objects)
- **Recursive schema generation**: Automatically generates nested JSON Schema from hierarchical field definitions
- **Arbitrary nesting depth**: Support for objects within objects, arrays of objects, and any combination thereof

### Enhanced

- **`input_field` and `output_field` macros**: Now accept optional do-blocks for defining nested structures
- **Schema generation**: Extended to recursively process and validate nested field definitions
- **Compile-time validation**: Validates nested structure definitions during compilation

### API Examples

**Nested Objects:**
```elixir
tool "create_user", "Creates a user", UserController, :create do
  input_field("user", "User data", :object, required: true) do
    field("name", "Full name", :string, required: true)
    field("email", "Email address", :string, required: true)

    field("address", "Mailing address", :object, required: true) do
      field("street", "Street address", :string)
      field("city", "City name", :string, required: true)
      field("country", "Country code", :string, required: true)
    end
  end
end
```

**Arrays with Complex Items:**
```elixir
tool "batch_create", "Batch create users", UserController, :batch do
  input_field("users", "List of users", :array, required: true) do
    items :object do
      field("name", "User name", :string, required: true)
      field("email", "Email", :string, required: true)
      field("roles", "User roles", :array, items: :string)
    end
  end
end
```

**Mixed Nesting:**
```elixir
input_field("project", "Project data", :object) do
  field("name", "Project name", :string, required: true)

  field("team", "Team members", :array) do
    items :object do
      field("user_id", "User ID", :string, required: true)
      field("role", "Role", :string, enum: ["admin", "developer", "viewer"])
      field("permissions", "Permissions", :array, items: :string)
    end
  end

  field("metadata", "Metadata", :object) do
    field("tags", "Tags", :array, items: :string)
  end
end
```

### Backward Compatibility

- **100% backward compatible**: All existing simple field definitions continue to work without modification
- **No breaking changes**: Do-blocks are optional; flat field definitions work as before
- **All tests passing**: 187 tests including 55+ existing tests and 100+ new nested structure tests

### Fixed

- Fixed pattern matching order for distinguishing do-blocks from option lists
- Fixed Map.reject removing valid empty required arrays in nested schemas
- Removed unused helper functions to eliminate compiler warnings

## [0.4.0] - 2025-10-21

### 🎉 Major Release: Struct-Based API

This release introduces typed Elixir structs throughout the MCP server library, replacing the previous map-based approach.

### ⚠️ Breaking Changes

- **Router list functions** now require `conn` parameter:
  - `tools_list()` → `list_tools(conn)`
  - `prompts_list()` → `prompts_list(conn)`
- **Controller functions** now require `conn` as first parameter:
  - Tool functions: arity 1 → 2
  - Prompt functions: arity 1 → 2 (get), arity 2 → 3 (complete)
  - Resource functions: arity 1 → 2 (read), arity 2 → 3 (complete)
- **Return values** are now typed structs instead of plain maps
- **Field access** changed from `["field"]` to `.field`

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for complete upgrade instructions.

### ✨ Added

- **16 new struct types** for MCP protocol structures:
  - `McpServer.Tool` and `Tool.Annotations`
  - `McpServer.Prompt`, `Prompt.Argument`, `Prompt.Message`, `Prompt.MessageContent`
  - `McpServer.Resource`, `McpServer.ResourceTemplate`
  - `McpServer.Resource.Content`, `Resource.ReadResult`
  - `McpServer.Completion`
  - `McpServer.Schema`
- **Helper functions**: All structs include `new/1` constructors
- **Automatic JSON encoding**: All structs implement `Jason.Encoder` with camelCase conversion
- **Compile-time validation**: `@enforce_keys` ensures required fields are present
- **Connection context**: `conn` parameter provides session info and private data

### 🔧 Changed

- Router DSL now generates typed structs instead of maps
- Controller helper functions return structs
- All list functions return `{:ok, [struct]}` tuples

### 📚 Documentation

- Added `MIGRATION_GUIDE.md` - Step-by-step migration instructions
- Added `QUICK_MIGRATION_REFERENCE.md` - Quick reference card
- Added `STRUCTURES.md` - Complete struct reference
- Added `CHANGELOG_v0.4.0.md` - Detailed v0.4.0 release notes
- Added `DOCUMENTATION_INDEX.md` - Documentation navigator
- Updated README with v0.4.0 examples and migration notice

### 🐛 Fixed

- Fixed inconsistent field naming between Elixir and JSON
- Fixed missing field validation in controller responses
- Fixed optional field handling (nil values properly omitted)

## [0.3.0] - 2025-10-15

### Added

- Initial public release
- Router DSL for defining tools, prompts, and resources
- HTTP transport via Bandit/Cowboy
- Input validation and schema generation
- Prompt argument completion support
- Resource URI templates
- Basic controller helpers

### Changed

- N/A (initial release)

### Fixed

- N/A (initial release)

## Links

- [0.8.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.7.0...v0.8.0
- [0.7.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.6.0...v0.7.0
- [0.6.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.5.0...v0.6.0
- [0.5.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.4.0...v0.5.0
- [0.4.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.3.0...v0.4.0
- [0.3.0]: https://github.com/GuillaumeMilan/mcp_server/releases/tag/v0.3.0
