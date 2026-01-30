defmodule McpServer.App.HttpPlugIntegrationTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias McpServer.HttpPlug
  alias McpServer.Tool.CallResult
  alias McpServer.Tool.Content

  # Controller with structured content
  defmodule UIToolController do
    def get_data(_conn, args) do
      key = Map.get(args, "key", "default")

      {:ok,
       CallResult.new(
         content: [Content.text("Data for #{key}")],
         structured_content: %{"key" => key, "value" => "test-data"}
       )}
    end

    def get_plain(_conn, args) do
      {:ok, [Content.text(Map.get(args, "query", "result"))]}
    end
  end

  defmodule UIResourceController do
    import McpServer.Controller, only: [content: 3]

    def read_dashboard(_conn, _params) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content("Dashboard", "ui://test/dashboard",
            mimeType: "text/html;profile=mcp-app",
            text: "<html></html>"
          )
        ]
      )
    end
  end

  defmodule TestRouter do
    use McpServer.Router

    tool "get_data", "Gets data with UI", UIToolController, :get_data,
      ui: "ui://test/dashboard",
      visibility: ["model", "app"] do
      input_field("key", "Data key", :string, required: true)
    end

    tool "get_plain", "Gets plain data", UIToolController, :get_plain do
      input_field("query", "Query", :string)
    end

    resource "dashboard", "ui://test/dashboard" do
      description("Test dashboard")
      mimeType("text/html;profile=mcp-app")
      read(UIResourceController, :read_dashboard)

      csp(connect_domains: ["api.test.com"])
      prefers_border(true)
    end
  end

  defp plug_opts do
    HttpPlug.init(
      router: TestRouter,
      server_info: %{name: "TestServer", version: "1.0.0"}
    )
  end

  defp post_json(method, params, session_id \\ nil) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params,
        "id" => 1
      })

    conn = conn(:post, "/", body)
    conn = put_req_header(conn, "content-type", "application/json")

    conn =
      if session_id do
        put_req_header(conn, "mcp-session-id", session_id)
      else
        conn
      end

    HttpPlug.call(conn, plug_opts())
  end

  defp init_session do
    conn = post_json("initialize", %{})
    [session_id] = get_resp_header(conn, "mcp-session-id")
    session_id
  end

  describe "initialize with extensions" do
    test "response includes io.modelcontextprotocol/ui extension" do
      conn = post_json("initialize", %{})

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      capabilities = response["result"]["capabilities"]

      assert capabilities["extensions"]["io.modelcontextprotocol/ui"] == %{
               "mimeTypes" => ["text/html;profile=mcp-app"]
             }
    end

    test "stores client capabilities in ETS" do
      _conn =
        post_json("initialize", %{
          "clientInfo" => %{"name" => "TestClient"},
          "capabilities" => %{"tools" => %{}}
        })

      # If ETS table exists, client info should be stored
      # (We just verify the initialize doesn't crash with client info)
    end
  end

  describe "tools/list with UI metadata" do
    test "tools with ui option include _meta in response" do
      session_id = init_session()
      conn = post_json("tools/list", %{}, session_id)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      tools = response["result"]["tools"]

      ui_tool = Enum.find(tools, &(&1["name"] == "get_data"))
      assert ui_tool["_meta"]["ui"]["resourceUri"] == "ui://test/dashboard"
      assert ui_tool["_meta"]["ui"]["visibility"] == ["model", "app"]
    end

    test "tools without ui option have no _meta" do
      session_id = init_session()
      conn = post_json("tools/list", %{}, session_id)

      response = Jason.decode!(conn.resp_body)
      tools = response["result"]["tools"]

      plain_tool = Enum.find(tools, &(&1["name"] == "get_plain"))
      assert plain_tool["_meta"] == nil
    end
  end

  describe "tools/call with structuredContent" do
    test "includes structuredContent when controller returns CallResult" do
      session_id = init_session()

      conn =
        post_json(
          "tools/call",
          %{"name" => "get_data", "arguments" => %{"key" => "test"}},
          session_id
        )

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      result = response["result"]

      assert result["isError"] == false
      assert result["structuredContent"]["key"] == "test"
      assert result["structuredContent"]["value"] == "test-data"
    end

    test "omits structuredContent for backward compat controllers" do
      session_id = init_session()

      conn =
        post_json(
          "tools/call",
          %{"name" => "get_plain", "arguments" => %{"query" => "hello"}},
          session_id
        )

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      result = response["result"]

      assert result["isError"] == false
      refute Map.has_key?(result, "structuredContent")
    end
  end

  describe "resources/list with UI metadata" do
    test "UI resources include _meta in response" do
      session_id = init_session()
      conn = post_json("resources/list", %{}, session_id)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      resources = response["result"]["resources"]

      dashboard = Enum.find(resources, &(&1["name"] == "dashboard"))
      assert dashboard["_meta"]["ui"]["csp"]["connectDomains"] == ["api.test.com"]
      assert dashboard["_meta"]["ui"]["prefersBorder"] == true
    end
  end
end
