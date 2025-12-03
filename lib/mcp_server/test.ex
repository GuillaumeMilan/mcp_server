defmodule McpServer.Test do
  @moduledoc """
  Test utilities for MCP Server routers.

  Provides two testing approaches:

  ## Approach 1: Direct Function Calls (Fast)

  Direct calls to router functions, bypassing HTTP/JSON-RPC layer.
  Best for unit testing individual tools, prompts, and resources.

      defmodule MyApp.McpRouterTest do
        use ExUnit.Case
        use McpServer.Test, router: MyApp.McpRouter

        test "search tool returns results" do
          result = call_tool("search", %{query: "test"})
          assert {:ok, contents} = result
          assert [%McpServer.Tool.Content.Text{text: text}] = contents
          assert text =~ "found"
        end

        test "code_review prompt generates messages" do
          {:ok, messages} = get_prompt("code_review", %{code: "def foo, do: :bar"})
          assert length(messages) == 2
        end

        test "list all tools" do
          {:ok, tools} = list_tools()
          assert length(tools) > 0
        end
      end

  ## Approach 2: Full Request Simulation (Comprehensive)

  Simulates complete JSON-RPC request lifecycle through the HTTP plug.
  Tests serialization, protocol compliance, and error handling.

      defmodule MyApp.McpRouterIntegrationTest do
        use ExUnit.Case
        use McpServer.Test, router: MyApp.McpRouter

        test "search via JSON-RPC" do
          conn = init_session()

          {:ok, result} = request(conn, "tools/call", %{
            name: "search",
            arguments: %{query: "test"}
          })

          assert result["content"]
          assert [%{"type" => "text", "text" => text}] = result["content"]
        end

        test "handles invalid tool name" do
          conn = init_session()

          {:error, error} = request(conn, "tools/call", %{
            name: "nonexistent",
            arguments: %{}
          })

          assert error["code"] == -32602
        end

        test "full workflow" do
          conn = init_session()

          # List tools
          {:ok, tools_result} = request(conn, "tools/list")
          assert is_list(tools_result["tools"])

          # Call a tool
          {:ok, call_result} = request(conn, "tools/call", %{
            name: "search",
            arguments: %{query: "test"}
          })
          assert call_result["content"]
        end
      end

  ## Custom Connection State

  You can customize the MCP connection for testing:

      test "with custom session" do
        conn = mock_conn(session_id: "custom-session-123")
        result = call_tool("search", %{query: "test"}, conn)
        assert {:ok, _} = result
      end

      test "with private data" do
        conn = mock_conn()
               |> McpServer.Conn.put_private(:user_id, 42)
        result = call_tool("auth_tool", %{}, conn)
        assert {:ok, _} = result
      end
  """

  alias McpServer.{Conn, JsonRpc}

  @doc """
  Imports test utilities for the given router.

  ## Options

    * `:router` - Required. The router module to test.

  ## Example

      use McpServer.Test, router: MyApp.McpRouter
  """
  defmacro __using__(opts) do
    router = Keyword.fetch!(opts, :router)

    quote do
      import McpServer.Test, only: [mock_conn: 0, mock_conn: 1]

      @mcp_test_router unquote(router)

      # ===========================================
      # Approach 1: Direct Function Calls
      # ===========================================

      # Calls a tool directly on the router
      defp call_tool(name, args \\ %{}, conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.call_tool(conn, name, args)
      end

      # Gets a prompt directly from the router
      defp get_prompt(name, args \\ %{}, conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.get_prompt(conn, name, args)
      end

      # Completes a prompt argument
      defp complete_prompt(name, argument, prefix, conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.complete_prompt(conn, name, argument, prefix)
      end

      # Reads a resource by URI
      defp read_resource(uri, conn \\ nil) do
        conn = conn || mock_conn()
        McpServer.Test.read_resource_impl(@mcp_test_router, conn, uri)
      end

      # Completes a resource argument
      defp complete_resource(uri, argument, prefix, conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.complete_resource(conn, uri, argument, prefix)
      end

      # Lists all tools defined in the router
      defp list_tools(conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.list_tools(conn)
      end

      # Lists all prompts defined in the router
      defp list_prompts(conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.prompts_list(conn)
      end

      # Lists all resources defined in the router
      defp list_resources(conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.list_resources(conn)
      end

      # Lists all resource templates defined in the router
      defp list_resource_templates(conn \\ nil) do
        conn = conn || mock_conn()
        @mcp_test_router.list_templates_resource(conn)
      end

      # ===========================================
      # Approach 2: Full Request Simulation
      # ===========================================

      # Initializes a test session for full request simulation
      defp init_session(opts \\ []) do
        McpServer.Test.init_session_impl(@mcp_test_router, opts)
      end

      # Sends a JSON-RPC request through the full HTTP plug pipeline
      defp request(test_conn, method, params \\ %{}) do
        McpServer.Test.request_impl(test_conn, method, params)
      end

      # Sends a raw JSON-RPC request and returns the full response
      defp request_raw(test_conn, method, params \\ %{}) do
        McpServer.Test.request_raw_impl(test_conn, method, params)
      end
    end
  end

  # ===========================================
  # Public Helpers
  # ===========================================

  @doc """
  Creates a mock MCP connection for testing.

  ## Options

    * `:session_id` - Session ID (default: "test-session-123")
    * `:private` - Private data map (default: %{})

  ## Examples

      conn = mock_conn()
      conn = mock_conn(session_id: "custom-session")
      conn = mock_conn(private: %{user_id: 42})
  """
  def mock_conn(opts \\ []) do
    session_id = Keyword.get(opts, :session_id, "test-session-123")
    private = Keyword.get(opts, :private, %{})

    %Conn{
      session_id: session_id,
      private: private
    }
  end

  # ===========================================
  # Internal Implementation
  # ===========================================

  @doc false
  def read_resource_impl(router, conn, uri) do
    # Get all resources and templates
    {:ok, resources} = router.list_resources(conn)
    {:ok, templates} = router.list_templates_resource(conn)

    # First check exact match in resources
    case Enum.find(resources, &(&1.uri == uri)) do
      %{name: name} ->
        router.read_resource(conn, name, %{})

      nil ->
        # Try to match against templates
        case find_matching_template(templates, uri) do
          {name, variables} ->
            router.read_resource(conn, name, variables)

          nil ->
            {:error, "Resource not found: #{uri}"}
        end
    end
  end

  defp find_matching_template(templates, uri) do
    Enum.find_value(templates, fn template ->
      case extract_template_variables(template.uri_template, uri) do
        {:ok, variables} -> {template.name, variables}
        :error -> nil
      end
    end)
  end

  defp extract_template_variables(template, uri) do
    # Convert template to regex pattern
    # e.g., "file://{path}" -> "file://(?<path>.+)"
    pattern =
      template
      |> Regex.escape()
      |> String.replace(~r/\\{(\w+)\\}/, "(?<\\1>.+)")

    case Regex.compile("^#{pattern}$") do
      {:ok, regex} ->
        case Regex.named_captures(regex, uri) do
          nil -> :error
          captures -> {:ok, captures}
        end

      {:error, _} ->
        :error
    end
  end

  @doc false
  def init_session_impl(router, opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    server_info =
      Keyword.get(opts, :server_info, %{
        name: "test-server",
        version: "1.0.0"
      })

    %{
      router: router,
      session_id: session_id,
      server_info: server_info,
      request_id: 0
    }
  end

  @doc false
  def request_impl(test_conn, method, params) do
    case request_raw_impl(test_conn, method, params) do
      %JsonRpc.Response{result: result, error: nil} ->
        {:ok, result}

      %JsonRpc.Response{error: error} ->
        {:error, %{"code" => error.code, "message" => error.message, "data" => error.data}}
    end
  end

  @doc false
  def request_raw_impl(test_conn, method, params) do
    # Build JSON-RPC request
    request_id = test_conn.request_id + 1
    request = JsonRpc.new_request(method, params, request_id)

    # Create a Plug.Test connection
    plug_conn =
      Plug.Test.conn(:post, "/", Jason.encode!(JsonRpc.encode_request(request)))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("mcp-session-id", test_conn.session_id)

    # Custom init callback that reads session_id from header
    init_callback = fn conn ->
      session_id =
        case Plug.Conn.get_req_header(conn, "mcp-session-id") do
          [id] -> id
          _ -> test_conn.session_id
        end

      %Conn{session_id: session_id}
    end

    # Build plug options with custom init callback
    plug_opts =
      McpServer.HttpPlug.init(
        router: test_conn.router,
        server_info: test_conn.server_info,
        init: init_callback
      )

    # Call the plug
    result_conn = McpServer.HttpPlug.call(plug_conn, plug_opts)

    # Parse response
    body = result_conn.resp_body

    case Jason.decode(body) do
      {:ok, response_map} ->
        case JsonRpc.decode_response(response_map) do
          {:ok, response} -> response
          {:error, reason} -> raise "Failed to decode JSON-RPC response: #{reason}"
        end

      {:error, reason} ->
        raise "Failed to decode response body: #{inspect(reason)}"
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
