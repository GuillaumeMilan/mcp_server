# McpServer


McpServer is a DSL for defining Model Context Protocol (MCP) tools and routers in Elixir. It allows you to easily expose tool endpoints with input/output schemas and validation.

## Installation

1. **Add dependencies to your `mix.exs`:**

```elixir
def deps do
  [
    {:mcp_server, "~> 0.1.0"},
    {:bandit, "~> 1.0"} # HTTP server
  ]
end
```

2. **Define your MCP Router:**

Create a module that uses `McpServer.Router` and defines your tools. Example:

```elixir
defmodule MyAppMcp.MyController do
  def echo(args), do: Map.get(args, "message", "default")
  def greet(args), do: "Hello, #{Map.get(args, "name", "World")}, you are connected with the session #{Process.get(:session_id)}!"
  def calculate(args), do: Map.get(args, "a", 0) + Map.get(args, "b", 0)
end

defmodule MyApp.Router do
  use McpServer.Router

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
end
```

3. **Start the Bandit server with your router:**

Add to your application supervision tree:

```elixir
children = [
  {Bandit, plug: {
              McpServer.HttpPlug,
              router: MyApp.Router,
              server_info: %{name: "MyApp MCP Server", version: "1.0.0"}
            }, port: 4000}
]

opts = [strategy: :one_for_one, name: MyApp.Supervisor]
Supervisor.start_link(children, opts)
```

Your MCP server will now be running and serving your defined tools.

## Usage & Testing

You can also call your tools via the router module:

```elixir
iex> MyApp.Router.tools_call("echo", %{"message" => "Hello World"})
# => "Hello World"
```

List all tools and their schemas:

```elixir
iex> MyApp.Router.tools_list()
# => [%{"name" => "echo", ...}, ...]
```
