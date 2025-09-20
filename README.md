# McpServer


McpServer is a DSL for defining Model Context Protocol (MCP) tools, prompts, and routers in Elixir. It allows you to easily expose tool endpoints with input/output schemas and validation, as well as define interactive prompts with argument completion.

## Installation

1. **Add dependencies to your `mix.exs`:**

```elixir
def deps do
  [
    {:mcp_server, "~> 0.2.0"},
    {:bandit, "~> 1.0"} # HTTP server
  ]
end
```

2. **Define your MCP Router:**

Create a module that uses `McpServer.Router` and defines your tools and prompts. Example:

```elixir
defmodule MyApp.MyController do
  import McpServer.Prompt, only: [message: 3, completion: 2]
  
  # Tool functions
  def echo(args), do: Map.get(args, "message", "default")
  def greet(args), do: "Hello, #{Map.get(args, "name", "World")}, you are connected with the session #{Process.get(:session_id)}!"
  def calculate(args), do: Map.get(args, "a", 0) + Map.get(args, "b", 0)
  
  # Prompt functions
  def get_greet_prompt(%{"user_name" => user_name}) do
    [
      message("user", "text", "Hello #{user_name}! Welcome to our MCP server. How can I assist you today?"),
      message("assistant", "text", "I'm here to help you with any questions or tasks you might have.")
    ]
  end

  def complete_greet_prompt("user_name", user_name_prefix) do
    names = ["Alice", "Bob", "Charlie", "David"]
    filtered_names = Enum.filter(names, &String.starts_with?(&1, user_name_prefix))
    completion(filtered_names, total: 100, has_more: true)
  end

  # Resource reader example
  def read_user(%{"id" => id}) do
    %{
      "contents" => [
        McpServer.Resource.content(
          "User #{id}",
          "https://example.com/users/#{id}",
          mimeType: "application/json",
          text: "{\"id\": \"#{id}\", \"name\": \"User #{id}\"}",
          title: "User title #{id}"
        )
      ]
    }
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

1. **Get function** - Returns a list of messages:

```elixir
def get_prompt_name(%{"arg_name" => value}) do
  [
    message("user", "text", "User message with #{value}"),
    message("assistant", "text", "Assistant response"),
    message("system", "text", "System instructions")
  ]
end
```

2. **Complete function** - Returns completion suggestions:

```elixir
def complete_prompt_name("arg_name", prefix) do
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

You can call your tools via the router module:

```elixir
iex> MyApp.Router.tools_call("echo", %{"message" => "Hello World"})
# => "Hello World"
```

List all tools and their schemas:

```elixir
iex> MyApp.Router.tools_list()
# => [%{"name" => "echo", ...}, ...]
```

### Testing Prompts

You can get prompt messages:

```elixir
iex> MyApp.Router.prompts_get("greet", %{"user_name" => "Alice"})
# => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello Alice! ..."}}, ...]
```

Get completion suggestions for prompt arguments:

```elixir
iex> MyApp.Router.prompts_complete("greet", "user_name", "A")
# => %{"values" => ["Alice"], "total" => 100, "hasMore" => true}
```

List all prompts:

```elixir
iex> MyApp.Router.prompts_list()
# => [%{"name" => "greet", "description" => "...", "arguments" => [...]}, ...]
```
