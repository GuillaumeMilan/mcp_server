# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- [0.4.0]: https://github.com/GuillaumeMilan/mcp_server/compare/v0.3.0...v0.4.0
- [0.3.0]: https://github.com/GuillaumeMilan/mcp_server/releases/tag/v0.3.0
