defmodule McpServer.TelemetryTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import McpServer.Controller, only: [message: 3, completion: 2, content: 3]

  # Flush all messages from mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  setup do
    flush_mailbox()
    :ok
  end

  # Test controller
  defmodule TestController do
    alias McpServer.Tool.Content, as: ToolContent

    def echo(_conn, args) do
      message = Map.get(args, "message", "default")
      [ToolContent.text(message)]
    end

    def failing_tool(_conn, _args) do
      raise "Tool failure"
    end

    def get_greet_prompt(_conn, %{"name" => name}) do
      [message("user", "text", "Hello #{name}!")]
    end

    def complete_greet_prompt(_conn, "name", prefix) do
      names = ["Alice", "Bob", "Charlie"]
      filtered = Enum.filter(names, &String.starts_with?(&1, prefix))
      completion(filtered, total: 3, has_more: false)
    end
  end

  # Test resource controller
  defmodule TestResourceController do
    def read_user(_conn, %{"id" => id}) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content(
            "User #{id}",
            "https://example.com/users/#{id}",
            mimeType: "application/json",
            text: "{\"id\": \"#{id}\"}"
          )
        ]
      )
    end

    def complete_user(_conn, "id", prefix) do
      ids = ["42", "43", "100"]
      filtered = Enum.filter(ids, &String.starts_with?(&1, prefix))
      completion(filtered, total: 3, has_more: false)
    end

    def read_static(_conn, _opts) do
      McpServer.Resource.ReadResult.new(
        contents: [
          content(
            "static.txt",
            "https://example.com/static",
            mimeType: "text/plain",
            text: "static content"
          )
        ]
      )
    end
  end

  # Test router
  defmodule TestRouter do
    use McpServer.Router

    tool "echo", "Echoes back the input", TestController, :echo do
      input_field("message", "The message to echo", :string, required: true)
    end

    tool "failing", "Always fails", TestController, :failing_tool do
      input_field("input", "Some input", :string)
    end

    prompt "greet", "A greeting prompt" do
      argument("name", "Name to greet", required: true)
      get(TestController, :get_greet_prompt)
      complete(TestController, :complete_greet_prompt)
    end

    resource "user", "https://example.com/users/{id}" do
      description("User resource")
      mimeType("application/json")
      read(TestResourceController, :read_user)
      complete(TestResourceController, :complete_user)
    end

    resource "static", "https://example.com/static" do
      description("Static resource")
      mimeType("text/plain")
      read(TestResourceController, :read_static)
    end
  end

  # Helper to set up telemetry handler
  defp attach_telemetry(test_pid, events) do
    handler_id = "test-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    handler_id
  end

  # Helper to make JSON-RPC request
  defp json_rpc_request(method, params, id \\ 1) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    })
  end

  # Helper to create a test connection
  defp create_conn(body, session_id \\ nil) do
    conn =
      Plug.Test.conn(:post, "/", body)
      |> put_req_header("content-type", "application/json")

    if session_id do
      put_req_header(conn, "mcp-session-id", session_id)
    else
      conn
    end
  end

  # Helper to call the plug
  defp call_plug(conn) do
    opts =
      McpServer.HttpPlug.init(
        router: TestRouter,
        server_info: %{name: "Test", version: "1.0"},
        init: fn plug_conn ->
          # Get session_id from header if present, otherwise nil
          session_id =
            case Plug.Conn.get_req_header(plug_conn, "mcp-session-id") do
              [id] -> id
              _ -> nil
            end

          %McpServer.Conn{session_id: session_id}
        end
      )

    McpServer.HttpPlug.call(conn, opts)
  end

  # Helper to initialize a session and get the session ID
  defp initialize_session do
    body = json_rpc_request("initialize", %{})
    conn = create_conn(body) |> call_plug()
    [session_id] = get_resp_header(conn, "mcp-session-id")
    # Flush any plug messages from initialization
    flush_mailbox()
    session_id
  end

  describe "HTTP request lifecycle telemetry" do
    test "emits request start and stop events" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :request, :start],
          [:mcp_server, :request, :stop]
        ])

      body = json_rpc_request("initialize", %{})
      create_conn(body) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :request, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.method == "POST"
      assert metadata.path == "/"

      assert_receive {:telemetry_event, [:mcp_server, :request, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.method == "initialize"
      assert metadata.status == 200

      :telemetry.detach(handler_id)
    end
  end

  describe "session lifecycle telemetry" do
    test "emits session init event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :session, :init]
        ])

      body = json_rpc_request("initialize", %{})
      conn = create_conn(body) |> call_plug()

      [session_id] = get_resp_header(conn, "mcp-session-id")

      assert_receive {:telemetry_event, [:mcp_server, :session, :init], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.protocol_version == "2025-06-18"

      :telemetry.detach(handler_id)
    end

    test "emits session initialized event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :session, :initialized]
        ])

      session_id = initialize_session()

      body = json_rpc_request("notifications/initialized", %{})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :session, :initialized], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end
  end

  describe "logging telemetry" do
    test "emits logging set_level event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :logging, :set_level]
        ])

      session_id = initialize_session()

      body = json_rpc_request("logging/setLevel", %{"level" => "debug"})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :logging, :set_level], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.level == "debug"

      :telemetry.detach(handler_id)
    end
  end

  describe "tool telemetry" do
    test "emits tool list event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :tool, :list]
        ])

      session_id = initialize_session()

      body = json_rpc_request("tools/list", %{})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :tool, :list], measurements, metadata}
      assert measurements.count == 2
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits tool call start and stop events on success" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :tool, :call_start],
          [:mcp_server, :tool, :call_stop]
        ])

      session_id = initialize_session()

      body =
        json_rpc_request("tools/call", %{"name" => "echo", "arguments" => %{"message" => "Hello"}})

      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :tool, :call_start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.tool_name == "echo"
      assert metadata.arguments == %{"message" => "Hello"}

      assert_receive {:telemetry_event, [:mcp_server, :tool, :call_stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.session_id == session_id
      assert metadata.tool_name == "echo"
      assert metadata.result_count == 1

      :telemetry.detach(handler_id)
    end

    test "emits tool call exception event on error" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :tool, :call_start],
          [:mcp_server, :tool, :call_exception]
        ])

      session_id = initialize_session()

      body = json_rpc_request("tools/call", %{"name" => "echo", "arguments" => %{}})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :tool, :call_start], _measurements,
                      _metadata}

      assert_receive {:telemetry_event, [:mcp_server, :tool, :call_exception], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.tool_name == "echo"
      assert metadata.error =~ "Missing required arguments"
      assert metadata.kind == :error

      :telemetry.detach(handler_id)
    end
  end

  describe "prompt telemetry" do
    test "emits prompt list event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :prompt, :list]
        ])

      session_id = initialize_session()

      body = json_rpc_request("prompts/list", %{})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :prompt, :list], measurements, metadata}
      assert measurements.count == 1
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits prompt get start and stop events on success" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :prompt, :get_start],
          [:mcp_server, :prompt, :get_stop]
        ])

      session_id = initialize_session()

      body =
        json_rpc_request("prompts/get", %{"name" => "greet", "arguments" => %{"name" => "Alice"}})

      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :prompt, :get_start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.prompt_name == "greet"
      assert metadata.arguments == %{"name" => "Alice"}

      assert_receive {:telemetry_event, [:mcp_server, :prompt, :get_stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.prompt_name == "greet"
      assert metadata.message_count == 1

      :telemetry.detach(handler_id)
    end

    test "emits prompt get exception event on error" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :prompt, :get_start],
          [:mcp_server, :prompt, :get_exception]
        ])

      session_id = initialize_session()

      body = json_rpc_request("prompts/get", %{"name" => "greet", "arguments" => %{}})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :prompt, :get_start], _measurements,
                      _metadata}

      assert_receive {:telemetry_event, [:mcp_server, :prompt, :get_exception], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.prompt_name == "greet"
      assert metadata.error =~ "Missing required arguments"
      assert metadata.kind == :error

      :telemetry.detach(handler_id)
    end
  end

  describe "resource telemetry" do
    test "emits resource list event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :resource, :list]
        ])

      session_id = initialize_session()

      body = json_rpc_request("resources/list", %{})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :resource, :list], measurements, metadata}
      assert measurements.count == 1
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits resource templates list event" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :resource, :templates_list]
        ])

      session_id = initialize_session()

      body = json_rpc_request("resources/templates/list", %{})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :resource, :templates_list], measurements,
                      metadata}

      assert measurements.count == 1
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits resource read start and stop events on success" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :resource, :read_start],
          [:mcp_server, :resource, :read_stop]
        ])

      session_id = initialize_session()

      # Flush any remaining messages before making the actual request
      flush_mailbox()

      # Use static resource for this test (exact URI match)
      body = json_rpc_request("resources/read", %{"uri" => "https://example.com/static"})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :resource, :read_start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.resource_uri == "https://example.com/static"
      assert metadata.resource_name == "static"
      assert metadata.template_vars == %{}

      assert_receive {:telemetry_event, [:mcp_server, :resource, :read_stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.resource_uri == "https://example.com/static"
      assert metadata.resource_name == "static"
      assert metadata.content_count == 1

      :telemetry.detach(handler_id)
    end

    test "emits resource read exception event on not found" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :resource, :read_exception]
        ])

      session_id = initialize_session()

      body = json_rpc_request("resources/read", %{"uri" => "https://example.com/unknown"})
      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :resource, :read_exception], measurements,
                      metadata}

      assert measurements.duration == 0
      assert metadata.session_id == session_id
      assert metadata.resource_uri == "https://example.com/unknown"
      assert metadata.error == "Resource not found"
      assert metadata.kind == :not_found

      :telemetry.detach(handler_id)
    end
  end

  describe "completion telemetry" do
    test "emits completion start and stop events for prompt completion" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :completion, :start],
          [:mcp_server, :completion, :stop]
        ])

      session_id = initialize_session()

      body =
        json_rpc_request("completion/complete", %{
          "ref" => %{"type" => "ref/prompt", "name" => "greet"},
          "argument" => %{"name" => "name", "value" => "A"}
        })

      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :completion, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.ref_type == "ref/prompt"
      assert metadata.ref_name == "greet"
      assert metadata.argument_name == "name"
      assert metadata.prefix == "A"

      assert_receive {:telemetry_event, [:mcp_server, :completion, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.ref_type == "ref/prompt"
      assert metadata.ref_name == "greet"
      assert metadata.completion_count == 1

      :telemetry.detach(handler_id)
    end

    test "emits completion exception event for resource not found" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :completion, :start],
          [:mcp_server, :completion, :exception]
        ])

      session_id = initialize_session()

      body =
        json_rpc_request("completion/complete", %{
          "ref" => %{"type" => "ref/resource", "uri" => "https://example.com/unknown"},
          "argument" => %{"name" => "id", "value" => "4"}
        })

      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :completion, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == session_id
      assert metadata.ref_type == "ref/resource"
      assert metadata.ref_name == "https://example.com/unknown"

      assert_receive {:telemetry_event, [:mcp_server, :completion, :exception], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.error =~ "not found"
      assert metadata.kind == :error

      :telemetry.detach(handler_id)
    end

    test "emits completion exception event on error" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :completion, :start],
          [:mcp_server, :completion, :exception]
        ])

      session_id = initialize_session()

      body =
        json_rpc_request("completion/complete", %{
          "ref" => %{"type" => "ref/prompt", "name" => "nonexistent"},
          "argument" => %{"name" => "arg", "value" => ""}
        })

      create_conn(body, session_id) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :completion, :start], _measurements,
                      _metadata}

      assert_receive {:telemetry_event, [:mcp_server, :completion, :exception], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.ref_type == "ref/prompt"
      assert metadata.ref_name == "nonexistent"
      assert metadata.error =~ "not found"
      assert metadata.kind == :error

      :telemetry.detach(handler_id)
    end
  end

  describe "validation error telemetry" do
    test "emits validation error event for invalid session" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :validation, :error]
        ])

      # Use a session ID that will fail base64 decoding (contains invalid characters)
      invalid_session = "!!!invalid!!!"
      body = json_rpc_request("tools/list", %{})
      create_conn(body, invalid_session) |> call_plug()

      assert_receive {:telemetry_event, [:mcp_server, :validation, :error], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.session_id == invalid_session
      assert metadata.type == :session_validation

      :telemetry.detach(handler_id)
    end
  end

  describe "JSON-RPC decode error telemetry" do
    test "emits decode error event for invalid JSON" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :json_rpc, :decode_error]
        ])

      conn =
        Plug.Test.conn(:post, "/", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> call_plug()

      assert conn.status == 400

      assert_receive {:telemetry_event, [:mcp_server, :json_rpc, :decode_error], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.error != nil

      :telemetry.detach(handler_id)
    end

    test "emits decode error event for invalid JSON-RPC format" do
      handler_id =
        attach_telemetry(self(), [
          [:mcp_server, :json_rpc, :decode_error]
        ])

      # Valid JSON but invalid JSON-RPC
      body = Jason.encode!(%{"not" => "jsonrpc"})

      conn =
        Plug.Test.conn(:post, "/", body)
        |> put_req_header("content-type", "application/json")
        |> call_plug()

      assert conn.status == 400

      assert_receive {:telemetry_event, [:mcp_server, :json_rpc, :decode_error], measurements,
                      _metadata}

      assert is_integer(measurements.system_time)

      :telemetry.detach(handler_id)
    end
  end
end
