# McpServer

[![Hex.pm](https://img.shields.io/hexpm/v/mcp_server.svg)](https://hex.pm/packages/mcp_server)
[![Hexdocs.pm](https://img.shields.io/badge/hexdocs-documentation-blue.svg)](https://hexdocs.pm/mcp_server)

McpServer is an Elixir library that builds a DSL for defining Model Context Protocol (MCP) tools, prompts, and routers in Elixir. It allows you to easily expose tool endpoints with input/output schemas and validation, as well as define interactive prompts with argument completion.

> **📢 Upgrading from v0.3.x?** See the [Migration Guide](MIGRATION_GUIDE.md) for a step-by-step upgrade path to v0.4.0's struct-based API.

## What's New in v0.4.0

Version 0.4.0 introduces **typed structs** throughout the library:

- ✨ **Type-safe structures**: All MCP protocol types are now proper Elixir structs with `@enforce_keys` validation
- 🔍 **Better IDE support**: Autocomplete and inline documentation for all struct fields
- 🛡️ **Compile-time safety**: Catch missing fields and typos at compile time, not runtime
- 📝 **Clearer code**: Use `.field` syntax instead of `["field"]` for accessing data
- 🔄 **Automatic JSON encoding**: All structs implement `Jason.Encoder` with proper camelCase conversion

**Breaking Changes:**
- Controller functions now require `conn` as first parameter (arity change)
- Router list functions renamed (e.g., `tools_list()` → `list_tools(conn)`)
- All functions return typed structs instead of plain maps

See [CHANGELOG_v0.4.0.md](CHANGELOG_v0.4.0.md) for complete details.

## Key Features

- **Type-Safe Structs**: All MCP protocol structures are now typed Elixir structs with compile-time validation
- **Connection Context**: All controller functions receive a `conn` parameter as their first argument, providing access to session information, user data, and other connection-specific context through `conn.session_id` and `conn.private`
- **Validated Tools**: Define tools with automatic input validation and output schemas
- **Interactive Prompts**: Create prompts with argument completion support
- **Resource Management**: Define and serve resources with URI templates
- **Automatic JSON Encoding**: All structs automatically encode to proper MCP JSON format

## Installation and setup

1. **Add dependencies to your `mix.exs`:**

```elixir
def deps do
  [
    {:mcp_server, "~> 0.4.0"},
    {:bandit, "~> 1.0"} # HTTP server
  ]
end
```

2. **Define your MCP Router:**

Create a module that uses `McpServer.Router` and defines your tools and prompts. Example:

```elixir
defmodule MyApp.MyController do
  import McpServer.Controller, only: [message: 3, completion: 2, content: 3]
  
  # Tool functions - all receive conn as first parameter
  def echo(_conn, args), do: Map.get(args, "message", "default")
  def greet(conn, args), do: "Hello, #{Map.get(args, "name", "World")}, you are connected with session #{conn.session_id}!"
  def calculate(_conn, args), do: Map.get(args, "a", 0) + Map.get(args, "b", 0)
  
  # Prompt functions - all receive conn as first parameter
  def get_greet_prompt(_conn, %{"user_name" => user_name}) do
    [
      message("user", "text", "Hello #{user_name}! Welcome to our MCP server. How can I assist you today?"),
      message("assistant", "text", "I'm here to help you with any questions or tasks you might have.")
    ]
  end

  def complete_greet_prompt(_conn, "user_name", user_name_prefix) do
    names = ["Alice", "Bob", "Charlie", "David"]
    filtered_names = Enum.filter(names, &String.starts_with?(&1, user_name_prefix))
    completion(filtered_names, total: 100, has_more: true)
  end

  # Resource reader example - receives conn as first parameter, returns ReadResult struct
  def read_user(_conn, %{"id" => id}) do
    McpServer.Resource.ReadResult.new(
      contents: [
        content(
          "User #{id}",
          "https://example.com/users/#{id}",
          mimeType: "application/json",
          text: "{\"id\": \"#{id}\", \"name\": \"User #{id}\"}",
          title: "User title #{id}"
        )
      ]
    )
  end
end

defmodule MyApp.Router do
  use McpServer.Router

  # Define tools
  tool "greet", "Greets a person", MyApp.MyController, :greet do
    input_field("name", "The name to greet", :string, required: false)
    output_field("greeting", "The greeting message", :string)
  end

  tool "calculate", "Adds two numbers", MyApp.MyController, :calculate do
    input_field("a", "First number", :integer, required: true)
    input_field("b", "Second number", :integer, required: true)
    output_field("result", "The sum of the numbers", :integer)
  end

  tool "echo", "Echoes back the input", MyApp.MyController, :echo,
    title: "Echo",
    hints: [:read_only, :non_destructive, :idempotent, :closed_world] do
    input_field("message", "The message to echo", :string, required: true)
    output_field("response", "The echoed message", :string)
  end

  # Define prompts
  prompt "greet", "A friendly greeting prompt that welcomes users" do
    argument("user_name", "The name of the user to greet", required: true)
    get MyApp.MyController, :get_greet_prompt
    complete MyApp.MyController, :complete_greet_prompt
  end

  # Define resources
  resource "user", "https://example.com/users/{id}" do
    description "User resource"
    mimeType "application/json"
    title "User title"
    read MyApp.MyController, :read_user
    complete MyApp.MyController, :complete_user
  end
end
```

3. **Start the Bandit server with your router:**

Add to your application supervision tree:

Make sure to respect the recommended [security options for MCP servers](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#security-warning)

```elixir
children = [
  {Bandit, plug: {
              McpServer.HttpPlug,
              router: MyApp.Router,
              server_info: %{name: "MyApp MCP Server", version: "1.0.0"}
            }, port: 4000, ip: {127, 0, 0, 1}}
]

opts = [strategy: :one_for_one, name: MyApp.Supervisor]
Supervisor.start_link(children, opts)
```

Your MCP server will now be running and serving your defined tools and prompts.

## Tools

Tools are functions that can be called by the MCP client. They support input validation and output schemas.

### Tool Definition

```elixir
tool "tool_name", "Description", ControllerModule, :function_name do
  input_field("param", "Parameter description", :type, required: true)
  output_field("result", "Result description", :type)
end
```

## Prompts

Prompts are interactive message templates with argument completion support. They're useful for generating structured conversations.

### Prompt Definition

```elixir
prompt "prompt_name", "Description" do
  argument("arg_name", "Argument description", required: true)
  get ControllerModule, :get_function
  complete ControllerModule, :complete_function
end
```

### Controller Implementation

Prompt controllers need two functions:

1. **Get function** - Receives `conn` and arguments, returns a list of messages:

```elixir
def get_prompt_name(conn, %{"arg_name" => value}) do
  # Access session info via conn.session_id or conn.private
  [
    message("user", "text", "User message with #{value}"),
    message("assistant", "text", "Assistant response"),
    message("system", "text", "System instructions")
  ]
end
```

2. **Complete function** - Receives `conn`, argument name, and prefix, returns completion suggestions:

```elixir
def complete_prompt_name(conn, "arg_name", prefix) do
  # Access session info via conn.session_id or conn.private
  suggestions = ["option1", "option2", "option3"]
  filtered = Enum.filter(suggestions, &String.starts_with?(&1, prefix))
  completion(filtered, total: 100, has_more: true)
end
```

### Helper Functions

The `McpServer.Prompt` module provides utility functions:

- `message(role, type, content)` - Creates message structures
- `completion(values, opts)` - Creates completion responses

## Usage & Testing

### Testing Tools

You can call your tools via the router module (note: you need to pass a connection):

```elixir
iex> conn = %McpServer.Conn{session_id: "test-session"}
iex> {:ok, result} = MyApp.Router.call_tool(conn, "echo", %{"message" => "Hello World"})
iex> result
# => "Hello World"
```

List all tools and their schemas (returns Tool structs):

```elixir
iex> conn = %McpServer.Conn{session_id: "test-session"}
iex> {:ok, tools} = MyApp.Router.list_tools(conn)
iex> hd(tools).name
# => "echo"
iex> hd(tools).description
# => "Echoes back the input"
```

### Testing Prompts

You can get prompt messages (returns Message structs):

```elixir
iex> conn = %McpServer.Conn{session_id: "test-session"}
iex> {:ok, messages} = MyApp.Router.get_prompt(conn, "greet", %{"user_name" => "Alice"})
iex> hd(messages).role
# => "user"
iex> hd(messages).content.text
# => "Hello Alice! Welcome to our MCP server..."
```

Get completion suggestions for prompt arguments (returns Completion struct):

```elixir
iex> conn = %McpServer.Conn{session_id: "test-session"}
iex> {:ok, completion} = MyApp.Router.complete_prompt(conn, "greet", "user_name", "A")
iex> completion.values
# => ["Alice"]
iex> completion.total
# => 100
iex> completion.has_more
# => true
```

List all prompts (returns Prompt structs):

```elixir
iex> conn = %McpServer.Conn{session_id: "test-session"}
iex> {:ok, prompts} = MyApp.Router.prompts_list(conn)
iex> hd(prompts).name
# => "greet"
iex> hd(prompts).description
# => "A friendly greeting prompt that welcomes users"
```
