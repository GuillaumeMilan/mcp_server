defmodule McpServer.HttpPlug do
  @moduledoc """
  HTTP Plug implementation for Model Context Protocol (MCP) servers.

  This module implements the MCP HTTP transport specification (2025-06-18), providing
  a complete JSON-RPC 2.0 over HTTP interface for MCP servers. It handles session
  management, request routing, and all standard MCP protocol methods.

  ## Features

  - **Session Management**: Automatic session ID generation and validation
  - **Tool Support**: List and execute tools defined in your router
  - **Prompt Support**: List, get, and complete prompts
  - **Resource Support**: List, read, and complete resources (static and template-based)
  - **Completion API**: Argument completion for prompts and resources

  ## Configuration Options

  When initializing the plug, you can provide the following options:

  ### Required Options

  * `:router` (required) - Module that uses `McpServer.Router`. This defines your
    tools, prompts, and resources. The plug will raise an `ArgumentError` if not provided.

  ### Optional Options

  * `:server_info` (optional) - Map containing server metadata returned during initialization.
    Defaults to `%{}`. Common fields include:
    * `:name` - Server name (string)
    * `:version` - Server version (string)

  * `:init` (optional) - Function that initializes the MCP connection from the Plug connection.
    Defaults to `fn plug_conn -> %McpServer.Conn{session_id: plug_conn.private.session_id} end`.
    This callback receives the `Plug.Conn` struct and must return a `%McpServer.Conn{}` struct.
    Use this to bridge authentication data or session information from upstream plugs
    (e.g., OAuth sessions) into your MCP connection context.

    Example with authentication bridge:
    ```elixir
    init: fn plug_conn ->
      user_id = plug_conn.assigns[:current_user_id]
      %McpServer.Conn{
        session_id: plug_conn.private.session_id,
        user_id: user_id
      }
    end
    ```

  ## Example Usage

  ### Basic Setup with Bandit

  ```elixir
  # In your application.ex supervision tree
  children = [
    {Bandit,
     plug: {McpServer.HttpPlug,
            router: MyApp.Router,
            server_info: %{name: "MyApp MCP Server", version: "1.0.0"}},
     port: 4000,
     ip: {127, 0, 0, 1}}  # Bind to localhost only for security
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
  ```

  ## Supported MCP Methods

  The plug implements the following MCP protocol methods:

  ### Initialization & Session Management

  * `initialize` - Initialize a new session and receive server capabilities
  * `notifications/initialized` - Client notification after initialization completes

  ### Tools

  * `tools/list` - List all available tools
  * `tools/call` - Execute a tool with arguments

  ### Prompts

  * `prompts/list` - List all available prompts
  * `prompts/get` - Get prompt messages with resolved arguments

  ### Resources

  * `resources/list` - List static resources
  * `resources/templates/list` - List resource templates
  * `resources/read` - Read a resource by URI

  ### Completion

  * `completion/complete` - Get argument completion suggestions for prompts or resources

  ### Logging

  * `logging/setLevel` - Set logging level for the current session

  ## Session Management

  The plug automatically manages sessions using the `mcp-session-id` header:

  1. **Session Creation**: When a client calls `initialize`, the server generates a
     unique session ID and returns it in the `mcp-session-id` response header.

  2. **Session Validation**: All subsequent requests (except `initialize` and
     `notifications/initialized`) must include the `mcp-session-id` header with
     a valid session ID.

  3. **Session Context**: The session ID is made available to your router functions
     via the passed connection to your router, allowing session-specific behavior in tools
     and prompts. To get the session see `McpServer.Conn.get_session_id/1`.

  ## HTTP Transport Details

  * **Method**: Only `POST` requests are supported. `GET` requests return 405.
  * **Content-Type**: Request and response bodies use `application/json; charset=utf-8`
  * **Headers**: They are not customizable for the moment, and include:
    * `cache-control: no-cache`
    * `connection: keep-alive`
    * `mcp-session-id: <session-id>` (after initialization)
  * **Body Limit**: Request bodies are limited to 1MB (1,000,000 bytes)

  ## Security Considerations

  ⚠️ **Important**: MCP servers should follow the security guidelines from the
  [MCP specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#security-warning):

  * Bind to localhost (`127.0.0.1`) only, not `0.0.0.0`
  * Use authentication/authorization if exposing over a network
  * Validate and sanitize all tool inputs
  * Run tools with minimal required privileges

  ## See Also

  * `McpServer.Router` - Define your MCP tools, prompts, and resources
  * `McpServer.JsonRpc` - JSON-RPC 2.0 encoding/decoding
  * `McpServer.URITemplate` - URI template matching for resources
  """
  use Plug.Builder
  require Logger
  alias McpServer.JsonRpc
  alias McpServer.Telemetry
  alias McpServer.URITemplate

  def init(opts) do
    router =
      Keyword.fetch(opts, :router)
      |> case do
        {:ok, router} -> router
        :error -> raise ArgumentError, "Router must be provided in options"
      end

    init_conn_callback =
      Keyword.get(opts, :init, fn plug_conn ->
        %McpServer.Conn{session_id: plug_conn.private.session_id}
      end)

    server_info =
      Keyword.get(opts, :server_info, %{})

    %{router: router, server_info: server_info, init_conn_callback: init_conn_callback}
  end

  def call(conn, _) when conn.method == "GET" do
    # We do not support SSE
    conn
    |> send_resp(405, "SSE not supported. Use POST.")
  end

  def call(conn, opts) when conn.method == "POST" do
    start_time = System.monotonic_time()

    Telemetry.execute(
      [:mcp_server, :request, :start],
      %{system_time: System.system_time()},
      %{method: conn.method, path: conn.request_path}
    )

    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    try do
      result_conn =
        conn
        |> setup_connection(opts)
        |> handle_body(body)
        |> halt()

      Telemetry.execute(
        [:mcp_server, :request, :stop],
        %{duration: System.monotonic_time() - start_time},
        %{
          session_id: result_conn.private[:session_id],
          method: result_conn.private[:json_rpc_method],
          status: result_conn.status
        }
      )

      result_conn
    rescue
      exception ->
        Telemetry.execute(
          [:mcp_server, :request, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{
            session_id: conn.private[:session_id],
            kind: :error,
            error: exception,
            stacktrace: __STACKTRACE__
          }
        )

        reraise exception, __STACKTRACE__
    end
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
    |> then(fn conn ->
      %McpServer.Conn{} = mcp_conn = opts.init_conn_callback.(conn)
      put_private(conn, :mcp_conn, mcp_conn)
    end)
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

      # Store the JSON-RPC method for telemetry
      conn = put_private(conn, :json_rpc_method, request.method)

      with :ok <- validate_session_when_needed(conn, request) do
        handle_request(conn, request)
      else
        {:error, reason} ->
          Logger.error("""
          Invalid session ID from session: #{inspect(session_id)}
          Reason: #{inspect(reason)}
          """)

          Telemetry.execute(
            [:mcp_server, :validation, :error],
            %{system_time: System.system_time()},
            %{
              session_id: session_id,
              type: :session_validation,
              error: reason
            }
          )

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

        # Convert error to string for telemetry and response
        error_string =
          case reason do
            %{__struct__: _} -> inspect(reason)
            _ when is_binary(reason) -> reason
            _ -> inspect(reason)
          end

        Telemetry.execute(
          [:mcp_server, :json_rpc, :decode_error],
          %{system_time: System.system_time()},
          %{
            session_id: session_id,
            error: error_string
          }
        )

        error_response =
          JsonRpc.new_error_response(-32700, "Parse error", error_string, nil)
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 400, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "initialize", id: id}) do
    # Generate a new session ID for initialization
    session_id = generate_session_id()

    Telemetry.execute(
      [:mcp_server, :session, :init],
      %{system_time: System.system_time()},
      %{
        session_id: session_id,
        protocol_version: "2025-06-18",
        server_info: conn.private.server_info
      }
    )

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
    |> put_private(:session_id, session_id)
    |> send_resp(200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "notifications/initialized"}) do
    # This is a notification (no id), so we don't send a response
    session_id = conn.private.session_id
    Logger.info("Client initialized for session: #{session_id}")

    Telemetry.execute(
      [:mcp_server, :session, :initialized],
      %{system_time: System.system_time()},
      %{session_id: session_id}
    )

    # Just return 202 Accepted for notifications
    send_resp(conn, 202, "")
  end

  def handle_request(conn, %JsonRpc.Request{method: "logging/setLevel", params: params, id: id}) do
    level = Map.get(params, "level")
    session_id = conn.private.session_id

    case set_logger_level(level, session_id) do
      :ok ->
        Logger.info("Logger level set to: #{level} for session: #{session_id}")

        Telemetry.execute(
          [:mcp_server, :logging, :set_level],
          %{system_time: System.system_time()},
          %{session_id: session_id, level: level}
        )

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
    mcp_conn = conn.private.mcp_conn

    case router.list_tools(mcp_conn) do
      {:ok, tools} ->
        Telemetry.execute(
          [:mcp_server, :tool, :list],
          %{count: length(tools)},
          %{session_id: session_id}
        )

        result = %{
          "tools" => tools
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Sending tools/list response for session: #{session_id}")
        Logger.debug("Tools list result: #{inspect(result)}")

        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        Logger.error("Failed to list tools for session #{session_id}: #{error_message}")

        error_response =
          JsonRpc.new_error_response(
            -32603,
            "Internal error",
            %{"message" => error_message},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 500, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "tools/call", params: params, id: id}) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn

    Logger.info(
      "Tool call request from session #{session_id} - Name: #{inspect(tool_name)}, Arguments: #{inspect(arguments)}"
    )

    start_time = System.monotonic_time()

    Telemetry.execute(
      [:mcp_server, :tool, :call_start],
      %{system_time: System.system_time()},
      %{session_id: session_id, tool_name: tool_name, arguments: arguments}
    )

    router.call_tool(mcp_conn, tool_name, arguments)
    |> case do
      {:ok, content} ->
        Telemetry.execute(
          [:mcp_server, :tool, :call_stop],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session_id, tool_name: tool_name, result_count: length(content)}
        )

        result = %{
          "content" => content,
          "isError" => false
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Tool call successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        Telemetry.execute(
          [:mcp_server, :tool, :call_exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session_id, tool_name: tool_name, error: error_message, kind: :error}
        )

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
        Telemetry.execute(
          [:mcp_server, :tool, :call_exception],
          %{duration: System.monotonic_time() - start_time},
          %{
            session_id: session_id,
            tool_name: tool_name,
            error: "Unexpected response format",
            kind: :error
          }
        )

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

  def handle_request(conn, %JsonRpc.Request{method: "resources/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn

    case router.list_resources(mcp_conn) do
      {:ok, resources} ->
        Telemetry.execute(
          [:mcp_server, :resource, :list],
          %{count: length(resources)},
          %{session_id: session_id}
        )

        result = %{
          "resources" => resources
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Sending resources/list response for session: #{session_id}")
        Logger.debug("Resources list result: #{inspect(result)}")

        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        Logger.error("Failed to list resources for session #{session_id}: #{error_message}")

        error_response =
          JsonRpc.new_error_response(
            -32603,
            "Internal error",
            %{"message" => error_message},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 500, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "resources/templates/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn

    case router.list_templates_resource(mcp_conn) do
      {:ok, templates} ->
        Telemetry.execute(
          [:mcp_server, :resource, :templates_list],
          %{count: length(templates)},
          %{session_id: session_id}
        )

        result = %{
          "resourceTemplates" => templates
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Sending resources/templates/list response for session: #{session_id}")
        Logger.debug("Resources templates list result: #{inspect(result)}")

        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        Logger.error(
          "Failed to list resource templates for session #{session_id}: #{error_message}"
        )

        error_response =
          JsonRpc.new_error_response(
            -32603,
            "Internal error",
            %{"message" => error_message},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 500, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "resources/read", params: params, id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn

    uri = Map.get(params, "uri")

    Logger.info("Resource read request from session #{session_id} - URI: #{inspect(uri)}")

    # Try to resolve the resource name/template via router.resources_list
    case find_matching_resource(router, uri) do
      {:ok, resource_name, vars} ->
        start_time = System.monotonic_time()

        Telemetry.execute(
          [:mcp_server, :resource, :read_start],
          %{system_time: System.system_time()},
          %{
            session_id: session_id,
            resource_uri: uri,
            resource_name: resource_name,
            template_vars: Map.new(vars)
          }
        )

        # delegate to router.read_resource with extracted variables
        case router.read_resource(mcp_conn, resource_name, Map.new(vars)) do
          {:ok, result} ->
            content_count =
              case result do
                %{"contents" => contents} when is_list(contents) -> length(contents)
                _ -> 1
              end

            Telemetry.execute(
              [:mcp_server, :resource, :read_stop],
              %{duration: System.monotonic_time() - start_time},
              %{
                session_id: session_id,
                resource_uri: uri,
                resource_name: resource_name,
                content_count: content_count
              }
            )

            response = JsonRpc.new_response(result, id)
            response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

            Logger.info("Resource read successful for session #{session_id}")
            send_resp(conn, 200, response_json)

          {:error, error_message} ->
            Telemetry.execute(
              [:mcp_server, :resource, :read_exception],
              %{duration: System.monotonic_time() - start_time},
              %{
                session_id: session_id,
                resource_uri: uri,
                resource_name: resource_name,
                error: error_message,
                kind: :error
              }
            )

            Logger.error("Resource read failed for session #{session_id}: #{error_message}")

            error_response =
              JsonRpc.new_error_response(
                -32603,
                "Internal error",
                %{"message" => error_message},
                id
              )
              |> JsonRpc.encode_response()
              |> Jason.encode!()

            send_resp(conn, 500, error_response)
        end

      :no_match ->
        Logger.error("Resource not found for URI: #{inspect(uri)}")

        Telemetry.execute(
          [:mcp_server, :resource, :read_exception],
          %{duration: 0},
          %{
            session_id: session_id,
            resource_uri: uri,
            error: "Resource not found",
            kind: :not_found
          }
        )

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

  # TODO this is a temporary implementation for prompts
  def handle_request(conn, %JsonRpc.Request{method: "prompts/list", id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn

    case router.prompts_list(mcp_conn) do
      {:ok, prompts} ->
        Telemetry.execute(
          [:mcp_server, :prompt, :list],
          %{count: length(prompts)},
          %{session_id: session_id}
        )

        result = %{
          "prompts" => prompts
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Sending prompts/list response for session: #{session_id}")
        Logger.debug("Prompts list result: #{inspect(result)}")

        send_resp(conn, 200, response_json)

      {:error, error_message} ->
        Logger.error("Failed to list prompts for session #{session_id}: #{error_message}")

        error_response =
          JsonRpc.new_error_response(
            -32603,
            "Internal error",
            %{"message" => error_message},
            id
          )
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        send_resp(conn, 500, error_response)
    end
  end

  def handle_request(conn, %JsonRpc.Request{method: "completion/complete", params: params, id: id}) do
    router = conn.private.router
    session_id = conn.private.session_id
    mcp_conn = conn.private.mcp_conn
    ref = Map.get(params, "ref")
    argument = Map.get(params, "argument")

    Logger.info(
      "Completion request from session #{session_id} - Ref: #{inspect(ref)}, Argument: #{inspect(argument)}"
    )

    ref_type = Map.get(ref, "type")
    ref_name = Map.get(ref, "name") || Map.get(ref, "uri")
    arg_name = Map.get(argument, "name")
    prefix = Map.get(argument, "value")

    start_time = System.monotonic_time()

    Telemetry.execute(
      [:mcp_server, :completion, :start],
      %{system_time: System.system_time()},
      %{
        session_id: session_id,
        ref_type: ref_type,
        ref_name: ref_name,
        argument_name: arg_name,
        prefix: prefix
      }
    )

    case handle_completion(router, mcp_conn, ref, argument) do
      {:ok, result} ->
        completion_count =
          case result do
            %{"completion" => %{"values" => values}} when is_list(values) -> length(values)
            %{"completion" => %McpServer.Completion{values: values}} -> length(values)
            _ -> 0
          end

        Telemetry.execute(
          [:mcp_server, :completion, :stop],
          %{duration: System.monotonic_time() - start_time},
          %{
            session_id: session_id,
            ref_type: ref_type,
            ref_name: ref_name,
            completion_count: completion_count
          }
        )

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Completion successful for session #{session_id}: #{inspect(result)}")
        send_resp(conn, 200, response_json)

      {:error, reason} ->
        Telemetry.execute(
          [:mcp_server, :completion, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{
            session_id: session_id,
            ref_type: ref_type,
            ref_name: ref_name,
            error: reason,
            kind: :error
          }
        )

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
    mcp_conn = conn.private.mcp_conn
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    Logger.info(
      "Prompt get request from session #{session_id} - Name: #{inspect(name)}, Arguments: #{inspect(arguments)}"
    )

    start_time = System.monotonic_time()

    Telemetry.execute(
      [:mcp_server, :prompt, :get_start],
      %{system_time: System.system_time()},
      %{session_id: session_id, prompt_name: name, arguments: arguments}
    )

    case router.get_prompt(mcp_conn, name, arguments) do
      {:ok, messages} ->
        Telemetry.execute(
          [:mcp_server, :prompt, :get_stop],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session_id, prompt_name: name, message_count: length(messages)}
        )

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
        Telemetry.execute(
          [:mcp_server, :prompt, :get_exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session_id, prompt_name: name, error: reason, kind: :error}
        )

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
  defp handle_completion(
         router,
         mcp_conn,
         %{"type" => "ref/prompt", "name" => prompt_name},
         argument
       ) do
    Logger.debug("Handling completion for prompt: #{prompt_name}, argument: #{inspect(argument)}")

    # Extract the argument name and prefix from the argument parameter
    case argument do
      %{"name" => arg_name, "value" => prefix} ->
        case router.complete_prompt(mcp_conn, prompt_name, arg_name, prefix) do
          {:ok, completion_result} ->
            result = %{
              "completion" => completion_result
            }

            {:ok, result}

          {:error, error_message} ->
            {:error, error_message}
        end

      _ ->
        {:error, "Invalid argument format for prompt completion"}
    end
  end

  defp handle_completion(
         router,
         mcp_conn,
         %{"type" => "ref/resource", "uri" => resource_uri},
         argument
       ) do
    Logger.debug(
      "Handling completion for resource: #{resource_uri}, argument: #{inspect(argument)}"
    )

    # Try to resolve resource name from templates and delegate to router.complete_resource
    # The argument is expected to be %{"name" => arg_name, "value" => prefix}
    case argument do
      %{"name" => arg_name, "value" => prefix} ->
        # Find resource by matching URI against templates
        case find_matching_resource(router, resource_uri) do
          {:ok, resource_name, _vars} ->
            case router.complete_resource(mcp_conn, resource_name, arg_name, prefix) do
              {:ok, completion_result} ->
                result = %{"completion" => completion_result}
                {:ok, result}

              {:error, error_message} ->
                {:error, error_message}
            end

          :no_match ->
            {:error, "Resource not found for completion"}
        end

      _ ->
        {:error, "Invalid argument format for resource completion"}
    end
  end

  defp handle_completion(_router, _mcp_conn, ref, _argument) do
    Logger.warning("Unsupported completion reference type: #{inspect(ref)}")
    {:error, "Unsupported reference type"}
  end

  # Try to find a matching resource for a given URI by comparing against router.resources_list()
  # Uses `McpServer.URITemplate` for template matching.
  defp find_matching_resource(router, uri) when is_binary(uri) do
    # First check static resources for exact match
    case router.list_resources(%McpServer.Conn{}) do
      {:ok, static_resources} ->
        case Enum.find(static_resources, fn res -> res.uri == uri end) do
          %{} = res ->
            {:ok, res.name, []}

          nil ->
            # Then check template resources using URITemplate.match/2
            case router.list_templates_resource(%McpServer.Conn{}) do
              {:ok, templates} ->
                templates
                |> Enum.find_value(:no_match, fn res ->
                  res_uri = res.uri_template

                  if is_binary(res_uri) do
                    tpl = URITemplate.new(res_uri)

                    case URITemplate.match(tpl, uri) do
                      {:ok, vars_map} when is_map(vars_map) ->
                        # Convert vars_map (map) into list of {var, value} as expected by callers
                        vars = Enum.map(vars_map, fn {k, v} -> {k, v} end)
                        {:ok, res.name, vars}

                      :nomatch ->
                        false

                      _ ->
                        false
                    end
                  else
                    false
                  end
                end)

              {:error, _} ->
                :no_match
            end
        end

      {:error, _} ->
        :no_match
    end
  end

  defp find_matching_resource(_router, _), do: :no_match
end
