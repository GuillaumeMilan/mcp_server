defmodule McpServer.App.HostPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias McpServer.App.HostPlug
  alias McpServer.App.HostCapabilities
  alias McpServer.App.HostContext

  # Test host implementation
  defmodule TestHost do
    @behaviour McpServer.App.Host

    @impl true
    def handle_initialize(_host_conn, _app_capabilities) do
      host_caps =
        HostCapabilities.new(
          open_links: %{},
          server_tools: %{list_changed: false},
          logging: %{}
        )

      host_ctx =
        HostContext.new(
          theme: "dark",
          display_mode: "inline",
          available_display_modes: ["inline", "fullscreen"],
          locale: "en-US"
        )

      {:ok, %{host_capabilities: host_caps, host_context: host_ctx}}
    end

    @impl true
    def handle_open_link(_host_conn, url) do
      if url == "https://error.example.com" do
        {:error, "Cannot open URL"}
      else
        :ok
      end
    end

    @impl true
    def handle_message(_host_conn, _role, _content) do
      :ok
    end

    @impl true
    def handle_request_display_mode(_host_conn, mode) do
      {:ok, mode}
    end

    @impl true
    def handle_update_model_context(_host_conn, _content, _structured_content) do
      :ok
    end

    @impl true
    def handle_size_changed(_host_conn, _width, _height) do
      :ok
    end

    @impl true
    def handle_teardown_response(_host_conn) do
      :ok
    end
  end

  # Test controller for proxied tool calls
  defmodule TestToolController do
    alias McpServer.Tool.Content

    def echo(_conn, args) do
      {:ok, [Content.text(Map.get(args, "message", "default"))]}
    end
  end

  # Test resource controller
  defmodule TestResourceController do
    import McpServer.Controller, only: [content: 3]

    def read_config(_conn, _params) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content("Config", "file:///config.json", mimeType: "application/json", text: "{}")
        ]
      )
    end
  end

  # Test router
  defmodule TestRouter do
    use McpServer.Router

    tool "echo", "Echoes input", TestToolController, :echo do
      input_field("message", "Message", :string, required: true)
    end

    resource "config", "file:///config.json" do
      description("App config")
      mimeType("application/json")
      read(TestResourceController, :read_config)
    end
  end

  defp plug_opts do
    HostPlug.init(host: TestHost, router: TestRouter)
  end

  defp json_rpc_request(method, params, id \\ 1) do
    Jason.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id})
  end

  defp post_json(body) do
    conn(:post, "/", body)
    |> put_req_header("content-type", "application/json")
    |> HostPlug.call(plug_opts())
  end

  describe "ui/initialize" do
    test "returns host capabilities and context" do
      body = json_rpc_request("ui/initialize", %{"appCapabilities" => %{}})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      result = response["result"]

      assert result["hostCapabilities"]["openLinks"] == %{}
      assert result["hostCapabilities"]["logging"] == %{}
      assert result["hostContext"]["theme"] == "dark"
      assert result["hostContext"]["displayMode"] == "inline"
      assert result["hostContext"]["locale"] == "en-US"
    end
  end

  describe "ui/open-link" do
    test "delegates to host callback" do
      body = json_rpc_request("ui/open-link", %{"url" => "https://example.com"})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end

    test "returns error on failure" do
      body = json_rpc_request("ui/open-link", %{"url" => "https://error.example.com"})
      conn = post_json(body)

      assert conn.status == 500
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["message"] == "Open link failed"
    end

    test "returns error on invalid params" do
      body = json_rpc_request("ui/open-link", %{})
      conn = post_json(body)

      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32602
    end
  end

  describe "ui/message" do
    test "delegates to host callback" do
      body =
        json_rpc_request("ui/message", %{
          "role" => "user",
          "content" => %{"type" => "text", "text" => "Hello"}
        })

      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end

    test "returns error on invalid params" do
      body = json_rpc_request("ui/message", %{"role" => "user"})
      conn = post_json(body)

      assert conn.status == 400
    end
  end

  describe "ui/request-display-mode" do
    test "delegates to host callback and returns actual mode" do
      body = json_rpc_request("ui/request-display-mode", %{"mode" => "fullscreen"})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"]["mode"] == "fullscreen"
    end
  end

  describe "ui/update-model-context" do
    test "delegates to host callback" do
      body =
        json_rpc_request("ui/update-model-context", %{
          "content" => [%{"type" => "text", "text" => "context"}],
          "structuredContent" => %{"key" => "value"}
        })

      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end
  end

  describe "ui/notifications/size-changed" do
    test "handles notification with 202" do
      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "ui/notifications/size-changed",
          "params" => %{"width" => 800, "height" => 600}
        })

      conn = post_json(body)
      assert conn.status == 202
    end
  end

  describe "ui/resource-teardown" do
    test "handles teardown with response" do
      body = json_rpc_request("ui/resource-teardown", %{"reason" => "navigation"})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end
  end

  describe "tools/call (proxied)" do
    test "proxies tool call to router" do
      body =
        json_rpc_request("tools/call", %{
          "name" => "echo",
          "arguments" => %{"message" => "hello"}
        })

      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"]["isError"] == false
    end

    test "returns error for unknown tool" do
      body =
        json_rpc_request("tools/call", %{
          "name" => "nonexistent",
          "arguments" => %{}
        })

      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"]["isError"] == true
    end
  end

  describe "resources/read (proxied)" do
    test "proxies resource read to router" do
      body = json_rpc_request("resources/read", %{"uri" => "file:///config.json"})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert is_map(response["result"])
    end

    test "returns error for unknown resource" do
      body = json_rpc_request("resources/read", %{"uri" => "file:///unknown"})
      conn = post_json(body)

      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32602
    end
  end

  describe "ping" do
    test "returns empty result" do
      body = json_rpc_request("ping", %{})
      conn = post_json(body)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end
  end

  describe "unknown method" do
    test "returns method not found error" do
      body = json_rpc_request("unknown/method", %{})
      conn = post_json(body)

      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32601
    end
  end

  describe "invalid request" do
    test "returns parse error for invalid JSON" do
      conn =
        conn(:post, "/", "not json")
        |> put_req_header("content-type", "application/json")
        |> HostPlug.call(plug_opts())

      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32700
    end

    test "rejects non-POST requests" do
      conn =
        conn(:get, "/")
        |> HostPlug.call(plug_opts())

      assert conn.status == 405
    end
  end

  describe "notification helpers" do
    test "notify_tool_input builds notification" do
      msg = HostPlug.notify_tool_input(%{"location" => "NYC"})
      assert msg["method"] == "ui/notifications/tool-input"
      assert msg["params"]["arguments"]["location"] == "NYC"
    end

    test "notify_tool_input_partial builds notification" do
      msg = HostPlug.notify_tool_input_partial(%{"loc" => "NY"})
      assert msg["method"] == "ui/notifications/tool-input-partial"
    end

    test "notify_tool_result builds notification" do
      result = %{"content" => [], "isError" => false}
      msg = HostPlug.notify_tool_result(result)
      assert msg["method"] == "ui/notifications/tool-result"
    end

    test "notify_tool_cancelled builds notification" do
      msg = HostPlug.notify_tool_cancelled("user_request")
      assert msg["method"] == "ui/notifications/tool-cancelled"
    end

    test "notify_host_context_changed builds notification" do
      msg = HostPlug.notify_host_context_changed(%{"theme" => "light"})
      assert msg["method"] == "ui/notifications/host-context-changed"
    end

    test "notify_resource_teardown builds request" do
      request = HostPlug.notify_resource_teardown("navigation", 42)
      assert request.method == "ui/resource-teardown"
      assert request.id == 42
    end
  end
end
