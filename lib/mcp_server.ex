defmodule McpServer do
  @moduledoc """
  Defines the behaviour for implementing Model Context Protocol (MCP) servers in Elixir.

  `McpServer` is the core behaviour module that specifies the callback functions
  required to implement a fully-functional MCP server. MCP (Model Context Protocol)
  is a protocol that enables AI models to interact with external tools, prompts,
  and resources.

  ## Overview

  This behaviour defines optional callbacks for three main MCP capabilities:

  1. **Tools** - Functions that can be called by MCP clients with input validation
  2. **Prompts** - Interactive message templates with argument completion
  3. **Resources** - Data sources that can be read and completed

  Implementing modules can choose to implement any combination of these capabilities
  by defining the appropriate callback functions.

  ## Callbacks

  All callbacks are optional, allowing servers to implement only the features they need:

  ### Tool Callbacks

  - `list_tools/1` - Returns the list of available tools with their schemas
  - `call_tool/3` - Executes a tool with the given name and arguments

  ### Prompt Callbacks

  - `get_prompt/3` - Returns a prompt's messages for the given arguments
  - `complete_prompt/3` - Provides completion suggestions for prompt arguments

  ### Resource Callbacks

  - `list_resources/1` - Returns the list of available resources
  - `read_resource/3` - Reads and returns a resource's contents
  - `complete_resource/3` - Provides completion suggestions for resource URIs

  ## Connection Context

  All callbacks receive a `McpServer.Conn.t()` as their first argument, which provides
  request context and connection information for handling the MCP interaction.

  ## Usage

  Instead of implementing this behaviour directly, most applications should use
  `McpServer.Router`, which provides a convenient DSL for defining tools, prompts,
  and resources:

      defmodule MyApp.Router do
        use McpServer.Router

        tool "greet", "Greets a person", MyController, :greet do
          input_field("name", "The name to greet", :string, required: true)
          output_field("greeting", "The greeting message", :string)
        end

        prompt "welcome", "A friendly welcome prompt" do
          argument("user_name", "The user's name", required: true)
          get MyController, :get_welcome_prompt
        end

        resource "user", "https://example.com/users/{id}" do
          description "User resource"
          read MyController, :read_user
        end
      end

  ## Error Handling

  Callbacks that can fail should return an `{:error, code, message}` tuple where:
  - `code` is an integer error code (typically JSON-RPC error codes)
  - `message` is a human-readable error description

  ## Example Implementation

      defmodule MyMcpServer do
        @behaviour McpServer

        @impl true
        def list_tools(_conn) do
          {:ok, [
            %{
              "name" => "echo",
              "description" => "Echoes back the input",
              "inputSchema" => %{
                "type" => "object",
                "properties" => %{"message" => %{"type" => "string"}},
                "required" => ["message"]
              }
            }
          ]}
        end

        @impl true
        def call_tool(_conn, "echo", %{"message" => msg}) do
          {:ok, %{"response" => msg}}
        end
      end

  See `McpServer.Router` for a more convenient way to define MCP servers.
  """

  alias McpServer.Conn

  @type error :: {:error, message :: String.t()}

  @callback list_tools(Conn.t()) :: {:ok, list()} | error()
  @callback call_tool(Conn.t(), String.t(), map()) :: {:ok, map()} | error()
  @callback get_prompt(Conn.t(), String.t(), map()) :: {:ok, list()} | error()
  @callback complete_prompt(
              Conn.t(),
              prompt_name :: String.t(),
              argument_name :: String.t(),
              prefix :: String.t()
            ) :: list() | error()
  @callback list_resources(Conn.t()) :: {:ok, list()} | error()
  @callback read_resource(Conn.t(), String.t(), map()) :: {:ok, any()} | error()
  @callback complete_resource(
              Conn.t(),
              resource_name :: String.t(),
              argument_name :: String.t(),
              prefix :: String.t()
            ) :: list() | error()

  @optional_callbacks list_tools: 1,
                      call_tool: 3,
                      get_prompt: 3,
                      complete_prompt: 3,
                      list_resources: 1,
                      read_resource: 3,
                      complete_resource: 3
end
