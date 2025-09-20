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

  def call(conn, _) when conn.method == "GET" do
    # We do not support SSE
    conn
    |> send_resp(405, "SSE not supported. Use POST.")
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
    |> put_resp_header("content-type", "application/json; charset=utf-8")
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
        "resources" => %{"listChanged" => true},
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

  def handle_request(conn, %JsonRpc.Request{method: "resources/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id

    result = %{
      "resources" => router.list_resource()
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending resources/list response for session: #{session_id}")
    Logger.debug("Resources list result: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "resources/templates/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id

    result = %{
      "resources" => router.list_templates_resource()
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending resources/templates/list response for session: #{session_id}")
    Logger.debug("Resources templates list result: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "resources/read", params: params, id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id

    uri = Map.get(params, "uri")

    Logger.info("Resource read request from session #{session_id} - URI: #{inspect(uri)}")

    # Try to resolve the resource name/template via router.resources_list
    case find_matching_resource(router, uri) do
      {:ok, resource_name, vars} ->
        # delegate to router.resources_read with extracted variables
        try do
          result = router.resources_read(resource_name, Map.new(vars))

          response = JsonRpc.new_response(result, id)
          response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

          send_resp(conn, 200, response_json)
        rescue
          e ->
            Logger.error("Resource read failed: #{inspect(e)}")

            error_response =
              JsonRpc.new_error_response(
                -32603,
                "Internal error",
                %{"message" => "Resource read failed"},
                id
              )
              |> JsonRpc.encode_response()
              |> Jason.encode!()

            send_resp(conn, 500, error_response)
        end

      :no_match ->
        error_response =
          JsonRpc.new_error_response(
            -32602,
            "Invalid params",
            %{"message" => "Resource not found"},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 400, error_response)
    end
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
    router = conn.private.router
    session_id = conn.private.session_id

    result = %{
      "prompts" => router.prompts_list()
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending prompts/list response for session: #{session_id}")
    Logger.debug("Prompts list result: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "completion/complete", params: params, id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    ref = Map.get(params, "ref")
    argument = Map.get(params, "argument")

    Logger.info(
      "Completion request from session #{session_id} - Ref: #{inspect(ref)}, Argument: #{inspect(argument)}"
    )

    case handle_completion(router, ref, argument) do
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

  def handle_request(conn, %JsonRpc.Request{method: "prompts/get", params: params, id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    Logger.info(
      "Prompt get request from session #{session_id} - Name: #{inspect(name)}, Arguments: #{inspect(arguments)}"
    )

    Process.put(:session_id, session_id)

    case router.prompts_get(name, arguments) do
      {:ok, messages} ->
        result = %{
          # TODO: Could be enhanced to include prompt description
          "description" => "Prompt response",
          "messages" => messages
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Prompt get successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      {:error, reason} ->
        Logger.error("Prompt get failed for session #{session_id}: #{reason}")

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

      messages when is_list(messages) ->
        result = %{
          "description" => "Prompt response",
          "messages" => messages
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Prompt get successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      _ ->
        Logger.error("Unexpected response format from prompt get for session #{session_id}")

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
  defp handle_completion(router, %{"type" => "ref/prompt", "name" => prompt_name}, argument) do
    Logger.debug("Handling completion for prompt: #{prompt_name}, argument: #{inspect(argument)}")

    # Extract the argument name and prefix from the argument parameter
    case argument do
      %{"name" => arg_name, "value" => prefix} ->
        try do
          completion_result = router.prompts_complete(prompt_name, arg_name, prefix)

          result = %{
            "completion" => completion_result
          }

          {:ok, result}
        catch
          :error, %ArgumentError{message: message} ->
            {:error, message}

          _, error ->
            {:error, "Completion failed: #{inspect(error)}"}
        end

      _ ->
        {:error, "Invalid argument format for prompt completion"}
    end
  end

  defp handle_completion(_router, %{"type" => "ref/resource", "uri" => resource_uri}, argument) do
    Logger.debug(
      "Handling completion for resource: #{resource_uri}, argument: #{inspect(argument)}"
    )

    # Return dummy response for resource completion - could be enhanced later
    result = %{
      "completion" => %{
        "values" => ["Example", "Instance", "Other"],
        "total" => 10,
        "hasMore" => true
      }
    }

    {:ok, result}
  end

  defp handle_completion(_router, ref, _argument) do
    Logger.warning("Unsupported completion reference type: #{inspect(ref)}")
    {:error, "Unsupported reference type"}
  end

  # Try to find a matching resource for a given URI by comparing against router.resources_list()
  defp find_matching_resource(router, uri) when is_binary(uri) do
    # First check static resources for exact match
    static_resources = router.list_resource()

    case Enum.find(static_resources, fn res -> Map.get(res, "uri") == uri end) do
      %{} = res ->
        {:ok, res["name"], []}

      nil ->
        # Then check template resources using template matching
        templates = router.list_templates_resource()

        templates
        |> Enum.find_value(:no_match, fn res ->
          res_uri = Map.get(res, "uri")

          case match_uri_template(res_uri, uri) do
            {:ok, vars} -> {:ok, res["name"], vars}
            :no_match -> false
          end
        end)
    end
  end

  defp find_matching_resource(_router, _), do: :no_match

  # Match a simple URI template like "https://example.com/users/{id}" against a concrete uri
  # Returns {:ok, [{var, value}...]} or :no_match
  defp match_uri_template(nil, _uri), do: :no_match

  defp match_uri_template(template, uri) do
    t_parts = String.split(template, "/", trim: true)
    u_parts = String.split(uri, "/", trim: true)

    if length(t_parts) != length(u_parts) do
      :no_match
    else
      Enum.zip(t_parts, u_parts)
      |> Enum.reduce_while({:ok, []}, fn
        {t_part, u_part}, {:ok, acc} ->
          case extract_var(t_part) do
            {:var, var_name} ->
              {:cont, {:ok, [{var_name, u_part} | acc]}}

            :no_var ->
              if t_part == u_part do
                {:cont, {:ok, acc}}
              else
                {:halt, :no_match}
              end
          end

        _, _ ->
          {:halt, :no_match}
      end)
      |> case do
        {:ok, vars} -> {:ok, vars}
        :no_match -> :no_match
      end
    end
  end

  defp extract_var(part) do
    case Regex.run(~r/^{(.+)}$/, part) do
      [_, var] -> {:var, var}
      _ -> :no_var
    end
  end
end
