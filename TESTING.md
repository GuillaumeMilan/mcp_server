# Testing MCP Server Routers

This guide covers the test utilities provided by `McpServer.Test` for testing MCP server routers. The module provides two complementary testing approaches to ensure comprehensive test coverage.

## Overview

The `McpServer.Test` module offers:

- **Approach 1: Direct Function Calls** - Fast unit tests that call router functions directly
- **Approach 2: Full Request Simulation** - Integration tests that simulate complete JSON-RPC requests through the HTTP plug

## Quick Start

```elixir
defmodule MyApp.McpRouterTest do
  use ExUnit.Case
  use McpServer.Test, router: MyApp.McpRouter

  test "search tool returns results" do
    result = call_tool("search", %{"query" => "test"})
    assert {:ok, contents} = result
  end
end
```

## Approach 1: Direct Function Calls

Direct calls bypass the HTTP/JSON-RPC layer, making them ideal for fast unit testing of individual tools, prompts, and resources.

### Testing Tools

```elixir
describe "tool tests" do
  test "call tool with valid arguments" do
    result = call_tool("search", %{"query" => "elixir"})

    assert {:ok, contents} = result
    assert [%McpServer.Tool.Content.Text{text: text}] = contents
    assert text =~ "results"
  end

  test "call tool with missing required argument" do
    result = call_tool("search", %{})

    assert {:error, message} = result
    assert message =~ "query"
  end

  test "call tool with custom connection" do
    conn = mock_conn(session_id: "custom-session")
    result = call_tool("search", %{"query" => "test"}, conn)

    assert {:ok, _} = result
  end
end
```

### Testing Prompts

```elixir
describe "prompt tests" do
  test "get prompt with valid arguments" do
    result = get_prompt("code_review", %{"code" => "def foo, do: :bar"})

    assert {:ok, messages} = result
    assert length(messages) == 2
    assert Enum.any?(messages, &(&1.role == "user"))
  end

  test "complete prompt argument" do
    result = complete_prompt("code_review", "language", "py")

    assert {:ok, completion} = result
    assert "python" in completion.values
  end
end
```

### Testing Resources

```elixir
describe "resource tests" do
  test "read static resource" do
    result = read_resource("config://app")

    assert {:ok, read_result} = result
    assert [content] = read_result.contents
    assert content.text
  end

  test "read templated resource" do
    # Automatically extracts template variables from URI
    result = read_resource("file:///home/user/config.json")

    assert {:ok, read_result} = result
    assert [content] = read_result.contents
    assert content.uri =~ "config.json"
  end

  test "complete resource argument" do
    result = complete_resource("file", "path", "/home")

    assert {:ok, completion} = result
    assert length(completion.values) > 0
  end
end
```

### Listing Definitions

```elixir
describe "listing tests" do
  test "list all tools" do
    {:ok, tools} = list_tools()

    assert length(tools) > 0
    assert Enum.any?(tools, &(&1.name == "search"))
  end

  test "list all prompts" do
    {:ok, prompts} = list_prompts()

    assert Enum.any?(prompts, &(&1.name == "code_review"))
  end

  test "list resources and templates" do
    {:ok, resources} = list_resources()
    {:ok, templates} = list_resource_templates()

    assert is_list(resources)
    assert is_list(templates)
  end
end
```

## Approach 2: Full Request Simulation

Full request simulation tests the complete JSON-RPC request lifecycle through the HTTP plug. This approach catches serialization issues, protocol compliance problems, and error handling.

### Session Management

```elixir
describe "session management" do
  test "initialize session with defaults" do
    conn = init_session()

    assert is_map(conn)
    assert is_binary(conn.session_id)
  end

  test "initialize session with custom options" do
    conn = init_session(
      session_id: "custom-session-id",
      server_info: %{name: "TestServer", version: "2.0"}
    )

    assert conn.session_id == "custom-session-id"
    assert conn.server_info.name == "TestServer"
  end
end
```

### Testing Tools via JSON-RPC

```elixir
describe "tools via JSON-RPC" do
  test "list tools" do
    conn = init_session()

    {:ok, result} = request(conn, "tools/list")

    assert is_list(result["tools"])
    assert length(result["tools"]) > 0
  end

  test "call tool" do
    conn = init_session()

    {:ok, result} = request(conn, "tools/call", %{
      name: "search",
      arguments: %{query: "test"}
    })

    assert result["content"]
    assert [%{"type" => "text", "text" => text}] = result["content"]
    assert is_binary(text)
  end

  test "tool error returns isError flag" do
    conn = init_session()

    {:ok, result} = request(conn, "tools/call", %{
      name: "nonexistent",
      arguments: %{}
    })

    # MCP returns tool errors as successful responses with isError flag
    assert result["isError"] == true
    assert [%{"text" => text}] = result["content"]
    assert text =~ "not found"
  end
end
```

### Testing Prompts via JSON-RPC

```elixir
describe "prompts via JSON-RPC" do
  test "list prompts" do
    conn = init_session()

    {:ok, result} = request(conn, "prompts/list")

    assert is_list(result["prompts"])
  end

  test "get prompt" do
    conn = init_session()

    {:ok, result} = request(conn, "prompts/get", %{
      name: "code_review",
      arguments: %{code: "def foo, do: :bar"}
    })

    assert result["messages"]
    assert length(result["messages"]) > 0
  end
end
```

### Testing Resources via JSON-RPC

```elixir
describe "resources via JSON-RPC" do
  test "list resources" do
    conn = init_session()

    {:ok, result} = request(conn, "resources/list")

    assert is_list(result["resources"])
  end

  test "list resource templates" do
    conn = init_session()

    {:ok, result} = request(conn, "resources/templates/list")

    assert is_list(result["resourceTemplates"])
  end

  test "read resource" do
    conn = init_session()

    {:ok, result} = request(conn, "resources/read", %{
      uri: "config://app"
    })

    assert result["contents"]
    assert [content] = result["contents"]
    assert content["text"] || content["blob"]
  end
end
```

### Testing Completions via JSON-RPC

```elixir
describe "completions via JSON-RPC" do
  test "complete prompt argument" do
    conn = init_session()

    {:ok, result} = request(conn, "completion/complete", %{
      ref: %{type: "ref/prompt", name: "code_review"},
      argument: %{name: "language", value: "py"}
    })

    assert result["completion"]
    assert is_list(result["completion"]["values"])
  end

  test "complete resource argument" do
    conn = init_session()

    {:ok, result} = request(conn, "completion/complete", %{
      ref: %{type: "ref/resource", uri: "file://{path}"},
      argument: %{name: "path", value: "/home"}
    })

    assert result["completion"]
    assert is_list(result["completion"]["values"])
  end
end
```

### Raw Response Testing

For testing protocol compliance and error responses, use `request_raw/3`:

```elixir
describe "protocol testing" do
  test "inspect raw JSON-RPC response" do
    conn = init_session()

    response = request_raw(conn, "tools/list")

    assert %McpServer.JsonRpc.Response{} = response
    assert response.jsonrpc == "2.0"
    assert response.result
    assert is_nil(response.error)
  end

  test "inspect error response" do
    conn = init_session()

    response = request_raw(conn, "invalid/method")

    assert %McpServer.JsonRpc.Response{} = response
    assert response.error
    assert response.error.code == -32601  # Method not found
  end
end
```

## Custom Connection State

For testing tools that depend on connection state, use `mock_conn/1`:

```elixir
describe "custom connection state" do
  test "with custom session ID" do
    conn = mock_conn(session_id: "test-session-123")
    result = call_tool("search", %{"query" => "test"}, conn)

    assert {:ok, _} = result
  end

  test "with private data" do
    conn = mock_conn(private: %{user_id: 42, role: :admin})

    # Access private data in your controller
    user_id = McpServer.Conn.get_private(conn, :user_id)
    assert user_id == 42
  end

  test "modify connection with Conn functions" do
    conn = mock_conn()
           |> McpServer.Conn.put_private(:request_id, "req-123")

    result = call_tool("audit_tool", %{}, conn)
    assert {:ok, _} = result
  end
end
```

## Full Workflow Testing

Test complete MCP interaction flows:

```elixir
describe "integration workflow" do
  test "complete MCP interaction" do
    conn = init_session()

    # 1. Discover available tools
    {:ok, tools} = request(conn, "tools/list")
    assert length(tools["tools"]) > 0

    # 2. Discover available prompts
    {:ok, prompts} = request(conn, "prompts/list")
    assert length(prompts["prompts"]) > 0

    # 3. Call a tool
    {:ok, tool_result} = request(conn, "tools/call", %{
      name: "search",
      arguments: %{query: "integration test"}
    })
    assert tool_result["content"]

    # 4. Get a prompt
    {:ok, prompt_result} = request(conn, "prompts/get", %{
      name: "code_review",
      arguments: %{code: "test code"}
    })
    assert prompt_result["messages"]

    # 5. Read a resource
    {:ok, resource_result} = request(conn, "resources/read", %{
      uri: "config://app"
    })
    assert resource_result["contents"]
  end
end
```

## API Reference

### Direct Call Functions (Approach 1)

| Function | Description |
|----------|-------------|
| `call_tool(name, args, conn \\ nil)` | Call a tool directly |
| `get_prompt(name, args, conn \\ nil)` | Get a prompt directly |
| `complete_prompt(name, argument, prefix, conn \\ nil)` | Complete a prompt argument |
| `read_resource(uri, conn \\ nil)` | Read a resource by URI |
| `complete_resource(name, argument, prefix, conn \\ nil)` | Complete a resource argument |
| `list_tools(conn \\ nil)` | List all tools |
| `list_prompts(conn \\ nil)` | List all prompts |
| `list_resources(conn \\ nil)` | List all resources |
| `list_resource_templates(conn \\ nil)` | List all resource templates |

### Request Simulation Functions (Approach 2)

| Function | Description |
|----------|-------------|
| `init_session(opts \\ [])` | Initialize a test session |
| `request(conn, method, params \\ %{})` | Send JSON-RPC request, return `{:ok, result}` or `{:error, error}` |
| `request_raw(conn, method, params \\ %{})` | Send JSON-RPC request, return raw `JsonRpc.Response` |

### Helper Functions

| Function | Description |
|----------|-------------|
| `mock_conn(opts \\ [])` | Create a mock MCP connection |

## Best Practices

1. **Use Approach 1 for unit tests** - Fast feedback, test individual components
2. **Use Approach 2 for integration tests** - Verify protocol compliance and serialization
3. **Test error cases** - Verify proper error handling for invalid inputs
4. **Test custom connection state** - If your tools use session data, test with custom connections
5. **Combine both approaches** - Use direct calls for logic testing, full simulation for end-to-end verification

## Troubleshooting

### Session ID Format Errors

If you see "Invalid session ID format" errors, ensure you're using `init_session/1` which generates properly formatted session IDs.

### Tool Errors vs Protocol Errors

MCP returns tool execution errors as successful responses with `isError: true`. Only protocol-level errors (invalid method, malformed request) return JSON-RPC error responses.

```elixir
# Tool error - returns {:ok, ...} with isError flag
{:ok, result} = request(conn, "tools/call", %{name: "nonexistent", arguments: %{}})
assert result["isError"] == true

# Protocol error - returns {:error, ...}
{:error, error} = request(conn, "invalid/method")
assert error["code"] == -32601
```

### Testing Templated Resources

The direct `read_resource/1` function automatically extracts template variables from URIs. For JSON-RPC testing, use the static resource URI or the template URI pattern.
