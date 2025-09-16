defmodule McpServer.HttpPlug do
  @moduledoc """
  This module implements the streamable HTTP standard for MCP servers.


  ## Example Usage

  ```elixir
  {Bandit, plug: {McpServer.HttpPlug, router: MyRouter, server_info: %{name: "MyServer", version: "1.0.0"}}, port: port}
  ```
  """
  use Plug.Builder
  require Logger
  alias McpServer.JsonRpc

  def init(opts) do
    router =
      Keyword.fetch(opts, :router)
      |> case do
        {:ok, router} -> router
        :error -> raise ArgumentError, "Router must be provided in options"
      end

    server_info =
      Keyword.get(opts, :server_info, %{})

    %{router: router, server_info: server_info}
  end

  def call(conn, opts) when conn.method == "GET" do
    # Not sure what to do for the moment
    conn
    |> setup_connection(opts)
    |> send_chunked(200)
    |> keep_alive()
  end

  def call(conn, opts) when conn.method == "POST" do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    conn
    |> setup_connection(opts)
    |> handle_body(body)
    |> halt()
  end

  # Session management
  @session_id_header "mcp-session-id"

  # Generate a session ID
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  # Extract session ID from request headers
  defp get_session_id(conn) do
    case Plug.Conn.get_req_header(conn, @session_id_header) do
      [session_id] -> session_id
      _ -> nil
    end
  end

  # Add session ID to response headers
  defp put_session_id_header(conn, session_id) do
    put_resp_header(conn, @session_id_header, session_id)
  end

  # Validate session ID format
  defp valid_session_id?(session_id) when is_binary(session_id) do
    Base.url_decode64(session_id, padding: false) != :error
  end

  defp valid_session_id?(_), do: false

  defp validate_session_when_needed(_, %JsonRpc.Request{method: method})
       when method in ["initialize", "notifications/initialized"] do
    # No session validation needed for initialization
    :ok
  end

  defp validate_session_when_needed(conn, _), do: validate_session(conn)

  # Validate that a session exists and is valid for non-initialization requests
  defp validate_session(conn) do
    case conn.private.session_id do
      nil ->
        error_response =
          JsonRpc.new_error_response(
            -32602,
            "Session required",
            %{"message" => "Session ID required for this request"},
            nil
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        {:error, error_response}

      session_id when is_binary(session_id) ->
        if valid_session_id?(session_id) do
          :ok
        else
          error_response =
            JsonRpc.new_error_response(
              -32602,
              "Invalid session",
              %{"message" => "Invalid session ID format"},
              nil
            )
            |> JsonRpc.encode_response()
            |> Jason.encode!()

          {:error, error_response}
        end

      _ ->
        error_response =
          JsonRpc.new_error_response(
            -32602,
            "Invalid session",
            %{"message" => "Invalid session ID"},
            nil
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        {:error, error_response}
    end
  end

  defp setup_connection(conn, opts) do
    session_id = get_session_id(conn)

    conn
    |> put_private(:router, opts.router)
    |> put_private(:server_info, opts.server_info)
    |> put_private(:session_id, session_id)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("content-type", "text/event-stream; charset=utf-8")
  end

  defp keep_alive(conn) do
    receive do
      :ok -> conn
    after
      120_000 -> conn
    end
  end

  def handle_body(conn, body) do
    with {:ok, map} <- Jason.decode(body),
         {:ok, request} <- JsonRpc.decode_request(map) do
      require Logger

      session_id = conn.private.session_id

      Logger.debug("""
      Received request from session: #{inspect(session_id)}
      Method: #{request.method}
      Request: #{inspect(request)}
      """)

      with :ok <- validate_session_when_needed(conn, request) do
        handle_request(conn, request)
      else
        {:error, reason} ->
          Logger.error("""
          Invalid session ID from session: #{inspect(session_id)}
          Reason: #{inspect(reason)}
          """)

          error_response =
            JsonRpc.new_error_response(-32602, "Invalid session", reason, request.id)
            |> JsonRpc.encode_response()
            |> Jason.encode!()

          send_resp(conn, 400, error_response)
      end

      handle_request(conn, request)
    else
      {:error, reason} ->
        session_id = conn.private.session_id

        Logger.error("""
        Failed to decode request from session: #{inspect(session_id)}
        Reason: #{inspect(reason)}
        Body: #{inspect(body)}
        """)

        error_response =
          JsonRpc.new_error_response(-32700, "Parse error", reason, nil)
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 400, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "initialize", id: id}) do
    # Generate a new session ID for initialization
    session_id = generate_session_id()

    result = %{
      "capabilities" => %{
        "completions" => %{},
        "logging" => %{},
        "prompts" => %{"listChanged" => true},
        "resources" => %{"listChanged" => true, "subscribe" => true},
        "tools" => %{"listChanged" => true}
      },
      # "instructions" => "Optional instructions for the client",
      "protocolVersion" => "2025-06-18",
      "serverInfo" => conn.private.server_info
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Initializing new session: #{session_id}")
    Logger.debug("Sending initialize response: #{inspect(response)}")

    conn
    |> put_session_id_header(session_id)
    |> send_resp(200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "notifications/initialized"}) do
    # This is a notification (no id), so we don't send a response
    session_id = conn.private.session_id
    Logger.info("Client initialized for session: #{session_id}")

    # Just return 200 OK for notifications
    send_resp(conn, 200, "")
  end

  def handle_request(conn, %JsonRpc.Request{method: "logging/setLevel", params: params, id: id}) do
    level = Map.get(params, "level")
    session_id = conn.private.session_id

    case set_logger_level(level, session_id) do
      :ok ->
        Logger.info("Logger level set to: #{level} for session: #{session_id}")

        # Return empty result for successful setLevel
        response = JsonRpc.new_response(%{}, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        send_resp(conn, 200, response_json)

      {:error, reason} ->
        Logger.error("Failed to set logger level for session #{session_id}: #{inspect(reason)}")

        error_response =
          JsonRpc.new_error_response(
            -32602,
            "Invalid params",
            %{"message" => "Invalid logging level: #{level}"},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 400, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "tools/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id

    result = %{
      "tools" => router.tools_list()
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending tools/list response for session: #{session_id}")
    Logger.debug("Tools list result: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "tools/call", params: params, id: id}) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})
    router = conn.private.router
    session_id = conn.private.session_id

    Logger.info(
      "Tool call request from session #{session_id} - Name: #{inspect(tool_name)}, Arguments: #{inspect(arguments)}"
    )

    Process.put(:session_id, session_id)

    router.tools_call(tool_name, arguments)
    |> case do
      {:ok, content} ->
        result = %{
          "content" => content,
          "isError" => false
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Tool call successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        result = %{
          "content" => [
            %{
              "type" => "text",
              "text" => "Error: #{error_message}"
            }
          ],
          "isError" => true
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.error("Tool call failed for session #{session_id}: #{error_message}")
        send_resp(conn, 200, response_json)

      _ ->
        Logger.error("Unexpected response format from tool call for session #{session_id}")

        error_response =
          JsonRpc.new_error_response(
            -32603,
            "Internal error",
            %{"message" => "Unexpected response format"},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 500, error_response)
    end
  end

  # TODO this is a temporary implementation for prompts
  def handle_request(conn, %JsonRpc.Request{method: "prompts/list", id: id}) do
    session_id = conn.private.session_id

    result = %{
      "prompts" => [
        %{
          "name" => "greeting_prompt",
          "description" => "A friendly greeting prompt that welcomes users",
          "arguments" => [
            %{
              "name" => "user_name",
              "description" => "The name of the user to greet",
              "required" => true
            }
          ]
        }
      ]
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending prompts/list response for session: #{session_id}")
    Logger.debug("Prompts list result: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "completion/complete", params: params, id: id}) do
    session_id = conn.private.session_id
    ref = Map.get(params, "ref")
    argument = Map.get(params, "argument")

    Logger.info("Completion request from session #{session_id} - Ref: #{inspect(ref)}, Argument: #{inspect(argument)}")

    case handle_completion(ref, argument) do
      {:ok, result} ->
        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Completion successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      {:error, reason} ->
        Logger.error("Completion failed for session #{session_id}: #{reason}")

        error_response =
          JsonRpc.new_error_response(
            -32602,
            "Invalid params",
            %{"message" => reason},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 400, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: method}) do
    session_id = conn.private.session_id
    Logger.warning("Unhandled method: #{inspect(method)} from session: #{inspect(session_id)}")

    error_response =
      JsonRpc.new_error_response(-32601, "Method not found", %{"method" => method}, nil)
      |> JsonRpc.encode_response()
      |> Jason.encode!()

    send_resp(conn, 501, error_response)
  end

  defp set_logger_level(level, session_id) do
    # TODO validate level and configure the logging session for the specific session
    Logger.info("Setting logger level to: #{inspect(level)}")

    if level in ["debug", "info", "notice", "warn", "error", "critical", "alert", "emergency"] do
      :ets.insert(McpServer.Session, {{session_id, :log_level}, level})
      :ok
    else
      {:error, "Invalid logging level"}
    end
  end

  # Handle completion requests for different reference types
  defp handle_completion(%{"type" => "ref/prompt", "name" => prompt_name}, argument) do
    Logger.debug("Handling completion for prompt: #{prompt_name}, argument: #{inspect(argument)}")

    # Return dummy response for prompt completion
    result = %{
      "completion" => %{
        "values" => ["Example", "Instance", "Other"],
        "total" => 10,
        "hasMore" => true
      }
    }

    {:ok, result}
  end

  defp handle_completion(%{"type" => "ref/resource", "uri" => resource_uri}, argument) do
    Logger.debug("Handling completion for resource: #{resource_uri}, argument: #{inspect(argument)}")

    # Return dummy response for resource completion
    result = %{
      "completion" => %{
        "values" => ["Example", "Instance", "Other"],
        "total" => 10,
        "hasMore" => true
      }
    }

    {:ok, result}
  end

  defp handle_completion(ref, _argument) do
    Logger.warning("Unsupported completion reference type: #{inspect(ref)}")
    {:error, "Unsupported reference type"}
  end
end
