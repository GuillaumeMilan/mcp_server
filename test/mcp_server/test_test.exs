defmodule McpServer.TestTest do
  use ExUnit.Case, async: true

  # ===========================================
  # Test Router Setup
  # ===========================================

  defmodule TestController do
    alias McpServer.Tool.Content, as: ToolContent

    def search(_conn, %{"query" => query}) do
      {:ok, [ToolContent.text("Found results for: #{query}")]}
    end

    def search(_conn, _args) do
      {:error, "Missing query parameter"}
    end

    def echo(_conn, args) do
      {:ok, [ToolContent.text("Echo: #{inspect(args)}")]}
    end

    def failing_tool(_conn, _args) do
      raise "Intentional error"
    end

    def code_review_get(_conn, %{"code" => code}) do
      [
        McpServer.Controller.message("user", "text", "Review this code: #{code}"),
        McpServer.Controller.message("assistant", "text", "Code looks good!")
      ]
    end

    def code_review_get(_conn, _args) do
      {:error, "Missing code parameter"}
    end

    def code_review_complete(_conn, "language", prefix) do
      values =
        ["elixir", "python", "javascript", "ruby"]
        |> Enum.filter(&String.starts_with?(&1, prefix))

      McpServer.Controller.completion(values, total: length(values))
    end

    def code_review_complete(_conn, _arg, _prefix) do
      McpServer.Controller.completion([], total: 0)
    end

    def read_file(_conn, %{"path" => path}) do
      McpServer.Resource.ReadResult.new(
        contents: [
          McpServer.Controller.content(
            Path.basename(path),
            "file://#{path}",
            text: "Content of #{path}"
          )
        ]
      )
    end

    def read_file(_conn, _opts) do
      {:error, "Missing path"}
    end

    def complete_file(_conn, "path", prefix) do
      values =
        ["/home/user/file1.txt", "/home/user/file2.txt", "/tmp/test.txt"]
        |> Enum.filter(&String.starts_with?(&1, prefix))

      McpServer.Controller.completion(values, total: length(values))
    end

    def complete_file(_conn, _arg, _prefix) do
      McpServer.Controller.completion([], total: 0)
    end

    def read_config(_conn, _opts) do
      McpServer.Resource.ReadResult.new(
        contents: [
          McpServer.Controller.content(
            "config.json",
            "config://app",
            text: ~s({"env": "test"})
          )
        ]
      )
    end
  end

  defmodule TestRouter do
    use McpServer.Router

    tool "search", "Search for items", TestController, :search do
      input_field("query", "Search query", :string, required: true)
    end

    tool "echo", "Echo back arguments", TestController, :echo do
      input_field("message", "Message to echo", :string)
    end

    tool "failing", "A tool that fails", TestController, :failing_tool do
      input_field("data", "Input data", :string)
    end

    prompt "code_review", "Review code for issues" do
      argument("code", "Code to review", required: true)
      argument("language", "Programming language")
      get(TestController, :code_review_get)
      complete(TestController, :code_review_complete)
    end

    resource "config", "config://app" do
      read(TestController, :read_config)
    end

    resource "file", "file://{path}" do
      read(TestController, :read_file)
      complete(TestController, :complete_file)
    end
  end

  # ===========================================
  # Test Module Using McpServer.Test
  # ===========================================

  use McpServer.Test, router: TestRouter

  # ===========================================
  # Approach 1: Direct Function Calls
  # ===========================================

  describe "call_tool/2" do
    alias McpServer.Tool.Content

    test "calls tool with valid arguments" do
      {:ok, [%Content.Text{text: text}]} = call_tool("search", %{"query" => "test"})
      assert text =~ "Found results for: test"
    end

    test "calls tool with missing required argument" do
      result = call_tool("search", %{})

      assert {:error, message} = result
      assert message =~ "query"
    end

    test "calls tool with custom connection" do
      conn = mock_conn(session_id: "custom-session")
      {:ok, [%Content.Text{text: text}]} = call_tool("echo", %{"message" => "hello"}, conn)
      assert text =~ "hello"
    end

    test "handles tool errors" do
      result = call_tool("failing", %{"data" => "test"})

      assert {:error, message} = result
      assert message =~ "Intentional error"
    end

    test "returns error for unknown tool" do
      result = call_tool("nonexistent", %{})

      assert {:error, _} = result
    end
  end

  describe "get_prompt/2" do
    test "gets prompt with valid arguments" do
      result = get_prompt("code_review", %{"code" => "def foo, do: :bar"})

      assert {:ok, messages} = result
      assert length(messages) == 2
      assert Enum.any?(messages, &(&1.role == "user"))
      assert Enum.any?(messages, &(&1.role == "assistant"))
    end

    test "returns error for missing required argument" do
      result = get_prompt("code_review", %{})

      assert {:error, message} = result
      assert message =~ "code"
    end

    test "returns error for unknown prompt" do
      result = get_prompt("nonexistent", %{})

      assert {:error, _} = result
    end
  end

  describe "complete_prompt/3" do
    test "completes prompt argument" do
      result = complete_prompt("code_review", "language", "eli")

      assert {:ok, completion} = result
      assert completion.values == ["elixir"]
    end

    test "returns empty for no matches" do
      result = complete_prompt("code_review", "language", "xyz")

      assert {:ok, completion} = result
      assert completion.values == []
    end
  end

  describe "read_resource/1" do
    test "reads static resource" do
      result = read_resource("config://app")

      assert {:ok, read_result} = result
      assert [content] = read_result.contents
      assert content.text =~ "test"
    end

    test "reads templated resource" do
      result = read_resource("file:///home/user/test.txt")

      assert {:ok, read_result} = result
      assert [content] = read_result.contents
      assert content.text =~ "/home/user/test.txt"
    end

    test "returns error for unknown resource" do
      result = read_resource("unknown://resource")

      assert {:error, message} = result
      assert message =~ "not found"
    end
  end

  describe "complete_resource/3" do
    test "completes resource argument" do
      # complete_resource takes the resource name, not the URI template
      result = complete_resource("file", "path", "/home")

      assert {:ok, completion} = result
      assert length(completion.values) == 2
    end
  end

  describe "list_tools/0" do
    test "lists all tools" do
      {:ok, tools} = list_tools()

      assert length(tools) == 3
      assert Enum.any?(tools, &(&1.name == "search"))
      assert Enum.any?(tools, &(&1.name == "echo"))
      assert Enum.any?(tools, &(&1.name == "failing"))
    end
  end

  describe "list_prompts/0" do
    test "lists all prompts" do
      {:ok, prompts} = list_prompts()

      assert length(prompts) == 1
      assert [prompt] = prompts
      assert prompt.name == "code_review"
    end
  end

  describe "list_resources/0" do
    test "lists static resources" do
      {:ok, resources} = list_resources()

      assert length(resources) == 1
      assert [resource] = resources
      assert resource.name == "config"
    end
  end

  describe "list_resource_templates/0" do
    test "lists resource templates" do
      {:ok, templates} = list_resource_templates()

      assert length(templates) == 1
      assert [template] = templates
      assert template.name == "file"
      assert template.uri_template == "file://{path}"
    end
  end

  # ===========================================
  # Approach 2: Full Request Simulation
  # ===========================================

  describe "init_session/0" do
    test "creates a test session" do
      conn = init_session()

      assert is_map(conn)
      assert conn.router == TestRouter
      assert is_binary(conn.session_id)
    end

    test "accepts custom session_id" do
      conn = init_session(session_id: "my-custom-session")

      assert conn.session_id == "my-custom-session"
    end

    test "accepts custom server_info" do
      conn = init_session(server_info: %{name: "my-server", version: "2.0"})

      assert conn.server_info.name == "my-server"
    end
  end

  describe "request/3 - tools" do
    test "lists tools via JSON-RPC" do
      conn = init_session()

      {:ok, result} = request(conn, "tools/list")

      assert is_list(result["tools"])
      assert length(result["tools"]) == 3

      tool_names = Enum.map(result["tools"], & &1["name"])
      assert "search" in tool_names
    end

    test "calls tool via JSON-RPC" do
      conn = init_session()

      {:ok, result} =
        request(conn, "tools/call", %{
          name: "search",
          arguments: %{query: "test"}
        })

      assert result["content"]
      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "Found results for: test"
    end

    test "returns error for unknown tool" do
      conn = init_session()

      # MCP returns tool errors as success with isError flag
      {:ok, result} =
        request(conn, "tools/call", %{
          name: "nonexistent",
          arguments: %{}
        })

      assert result["isError"] == true
      assert [%{"text" => text}] = result["content"]
      assert text =~ "not found"
    end

    test "returns error for missing arguments" do
      conn = init_session()

      # MCP returns tool errors as success with isError flag
      {:ok, result} =
        request(conn, "tools/call", %{
          name: "search",
          arguments: %{}
        })

      assert result["isError"] == true
      assert [%{"text" => text}] = result["content"]
      assert text =~ "query"
    end
  end

  describe "request/3 - prompts" do
    test "lists prompts via JSON-RPC" do
      conn = init_session()

      {:ok, result} = request(conn, "prompts/list")

      assert is_list(result["prompts"])
      assert length(result["prompts"]) == 1
      assert hd(result["prompts"])["name"] == "code_review"
    end

    test "gets prompt via JSON-RPC" do
      conn = init_session()

      {:ok, result} =
        request(conn, "prompts/get", %{
          name: "code_review",
          arguments: %{code: "def foo, do: :bar"}
        })

      assert result["messages"]
      assert length(result["messages"]) == 2
    end

    test "returns error for missing prompt arguments" do
      conn = init_session()

      {:error, error} =
        request(conn, "prompts/get", %{
          name: "code_review",
          arguments: %{}
        })

      assert error["code"] == -32602
    end
  end

  describe "request/3 - resources" do
    test "lists resources via JSON-RPC" do
      conn = init_session()

      {:ok, result} = request(conn, "resources/list")

      assert is_list(result["resources"])
      assert length(result["resources"]) == 1
    end

    test "lists resource templates via JSON-RPC" do
      conn = init_session()

      {:ok, result} = request(conn, "resources/templates/list")

      assert is_list(result["resourceTemplates"])
      assert length(result["resourceTemplates"]) == 1
    end

    test "reads resource via JSON-RPC" do
      conn = init_session()

      {:ok, result} =
        request(conn, "resources/read", %{
          uri: "config://app"
        })

      assert result["contents"]
      assert [content] = result["contents"]
      assert content["text"] =~ "test"
    end

    test "returns error for unknown resource via JSON-RPC" do
      conn = init_session()

      # Note: HttpPlug currently doesn't match templated resources
      # This tests the error case
      {:error, error} =
        request(conn, "resources/read", %{
          uri: "unknown://resource"
        })

      assert error["code"] == -32602
      assert error["message"] =~ "Invalid params"
    end
  end

  describe "request/3 - completion" do
    test "completes prompt argument via JSON-RPC" do
      conn = init_session()

      {:ok, result} =
        request(conn, "completion/complete", %{
          ref: %{type: "ref/prompt", name: "code_review"},
          argument: %{name: "language", value: "py"}
        })

      assert result["completion"]
      assert result["completion"]["values"] == ["python"]
    end

    test "completes resource argument via JSON-RPC" do
      conn = init_session()

      {:ok, result} =
        request(conn, "completion/complete", %{
          ref: %{type: "ref/resource", uri: "file://{path}"},
          argument: %{name: "path", value: "/tmp"}
        })

      assert result["completion"]
      assert result["completion"]["values"] == ["/tmp/test.txt"]
    end
  end

  describe "request_raw/3" do
    test "returns full JSON-RPC response" do
      conn = init_session()

      response = request_raw(conn, "tools/list")

      assert %McpServer.JsonRpc.Response{} = response
      assert response.result
      assert is_nil(response.error)
    end

    test "returns response for tool error" do
      conn = init_session()

      response =
        request_raw(conn, "tools/call", %{
          name: "nonexistent",
          arguments: %{}
        })

      # MCP returns tool errors as successful responses with isError flag
      assert %McpServer.JsonRpc.Response{} = response
      assert response.result["isError"] == true
    end
  end

  describe "full workflow" do
    test "complete MCP interaction flow" do
      conn = init_session()

      # 1. List available tools
      {:ok, tools_result} = request(conn, "tools/list")
      assert length(tools_result["tools"]) > 0

      # 2. List available prompts
      {:ok, prompts_result} = request(conn, "prompts/list")
      assert length(prompts_result["prompts"]) > 0

      # 3. Call a tool
      {:ok, tool_result} =
        request(conn, "tools/call", %{
          name: "search",
          arguments: %{query: "integration test"}
        })

      assert tool_result["content"]

      # 4. Get a prompt
      {:ok, prompt_result} =
        request(conn, "prompts/get", %{
          name: "code_review",
          arguments: %{code: "test code"}
        })

      assert prompt_result["messages"]

      # 5. Read a resource
      {:ok, resource_result} =
        request(conn, "resources/read", %{
          uri: "config://app"
        })

      assert resource_result["contents"]
    end
  end

  # ===========================================
  # mock_conn/1 tests
  # ===========================================

  describe "mock_conn/1" do
    test "creates default connection" do
      conn = mock_conn()

      assert %McpServer.Conn{} = conn
      assert conn.session_id == "test-session-123"
      assert conn.private == %{}
    end

    test "accepts custom session_id" do
      conn = mock_conn(session_id: "custom-id")

      assert conn.session_id == "custom-id"
    end

    test "accepts custom private data" do
      conn = mock_conn(private: %{user_id: 42, role: :admin})

      assert conn.private == %{user_id: 42, role: :admin}
    end

    test "connection can be modified with Conn functions" do
      conn =
        mock_conn()
        |> McpServer.Conn.put_private(:custom_key, "custom_value")

      assert McpServer.Conn.get_private(conn, :custom_key) == "custom_value"
    end
  end
end
