defmodule McpServer.App.HostPlug do
  @moduledoc """
  Plug for handling MCP Apps host-to-view communication.

  This plug acts as an HTTP endpoint that receives JSON-RPC messages from
  views (iframes) relayed through a frontend, dispatches them to the
  appropriate `McpServer.App.Host` callbacks, and proxies tool/resource
  calls to the MCP router.

  ## Configuration

      plug McpServer.App.HostPlug,
        host: MyApp.HostHandler,
        router: MyApp.Router,
        server_info: %{name: "MyApp", version: "1.0.0"}

  ## Options

  * `:host` (required) — Module implementing `McpServer.App.Host` behaviour.
  * `:router` (required) — Module using `McpServer.Router` for proxying
    `tools/call` and `resources/read` requests from views.
  * `:server_info` (optional) — Server metadata map. Defaults to `%{}`.
  * `:init` (optional) — Function `(Plug.Conn.t() -> map())` that builds
    the host connection context passed to callbacks. Defaults to `fn _ -> %{} end`.

  ## Supported Methods

  ### View-to-Host Requests
  * `ui/initialize` — View initialization handshake
  * `ui/open-link` — View requests host to open an external URL
  * `ui/message` — View sends a message to the chat
  * `ui/request-display-mode` — View requests a display mode change
  * `ui/update-model-context` — View updates the model context

  ### View-to-Host Notifications
  * `ui/notifications/size-changed` — View reports size change

  ### Proxied to Router
  * `tools/call` — View calls a server tool
  * `resources/read` — View reads a server resource

  ### Utility
  * `ping` — Health check (returns empty result)

  ## Sending Notifications to Views

  Use the helper functions to build notification messages that should be
  sent back to the view through your transport layer (e.g., WebSocket,
  postMessage relay):

      McpServer.App.HostPlug.notify_tool_input(arguments)
      McpServer.App.HostPlug.notify_tool_input_partial(arguments)
      McpServer.App.HostPlug.notify_tool_result(call_tool_result)
      McpServer.App.HostPlug.notify_tool_cancelled(reason)
      McpServer.App.HostPlug.notify_host_context_changed(partial_context)
      McpServer.App.HostPlug.notify_resource_teardown(reason, id)
  """

  use Plug.Builder
  require Logger
  alias McpServer.JsonRpc
  alias McpServer.App.Messages

  def init(opts) do
    host =
      Keyword.fetch(opts, :host)
      |> case do
        {:ok, host} -> host
        :error -> raise ArgumentError, "`:host` option is required for McpServer.App.HostPlug"
      end

    router =
      Keyword.fetch(opts, :router)
      |> case do
        {:ok, router} -> router
        :error -> raise ArgumentError, "`:router` option is required for McpServer.App.HostPlug"
      end

    init_host_conn = Keyword.get(opts, :init, fn _plug_conn -> %{} end)
    server_info = Keyword.get(opts, :server_info, %{})

    %{host: host, router: router, init_host_conn: init_host_conn, server_info: server_info}
  end

  def call(conn, _opts) when conn.method != "POST" do
    conn
    |> send_resp(405, "Method not allowed. Use POST.")
    |> halt()
  end

  def call(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    conn =
      conn
      |> put_resp_header("content-type", "application/json; charset=utf-8")
      |> put_resp_header("cache-control", "no-cache")

    with {:ok, map} <- Jason.decode(body),
         {:ok, request} <- JsonRpc.decode_request(map) do
      host_conn = opts.init_host_conn.(conn)
      handle_request(conn, request, opts, host_conn)
    else
      {:error, reason} ->
        error_string = if is_binary(reason), do: reason, else: inspect(reason)

        error_response =
          JsonRpc.new_error_response(-32700, "Parse error", error_string, nil)
          |> JsonRpc.encode_response()
          |> Jason.encode!()

        conn
        |> send_resp(400, error_response)
        |> halt()
    end
  end

  # ── ui/initialize ─────────────────────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/initialize", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_initialize_request(params || %{}) do
      {:ok, app_capabilities} ->
        case opts.host.handle_initialize(host_conn, app_capabilities) do
          {:ok, %{host_capabilities: host_caps, host_context: host_ctx}} ->
            response =
              Messages.encode_initialize_response(host_caps, host_ctx, id)
              |> JsonRpc.encode_response()
              |> Jason.encode!()

            conn |> send_resp(200, response) |> halt()

          {:error, reason} ->
            send_error(conn, -32603, "Initialize failed", reason, id)
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ui/open-link ──────────────────────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/open-link", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_open_link(params || %{}) do
      {:ok, url} ->
        if function_exported?(opts.host, :handle_open_link, 2) do
          case opts.host.handle_open_link(host_conn, url) do
            :ok ->
              send_result(conn, %{}, id)

            {:error, reason} ->
              send_error(conn, -32603, "Open link failed", reason, id)
          end
        else
          send_error(conn, -32601, "Method not supported", "Host does not support open-link", id)
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ui/message ────────────────────────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/message", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_message(params || %{}) do
      {:ok, %{role: role, content: content}} ->
        if function_exported?(opts.host, :handle_message, 3) do
          case opts.host.handle_message(host_conn, role, content) do
            :ok ->
              send_result(conn, %{}, id)

            {:error, reason} ->
              send_error(conn, -32603, "Message failed", reason, id)
          end
        else
          send_error(conn, -32601, "Method not supported", "Host does not support message", id)
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ui/request-display-mode ───────────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/request-display-mode", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_request_display_mode(params || %{}) do
      {:ok, mode} ->
        if function_exported?(opts.host, :handle_request_display_mode, 2) do
          case opts.host.handle_request_display_mode(host_conn, mode) do
            {:ok, actual_mode} ->
              send_result(conn, %{"mode" => actual_mode}, id)

            {:error, reason} ->
              send_error(conn, -32603, "Display mode change failed", reason, id)
          end
        else
          send_error(
            conn,
            -32601,
            "Method not supported",
            "Host does not support display mode changes",
            id
          )
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ui/update-model-context ───────────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/update-model-context", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_update_model_context(params || %{}) do
      {:ok, %{content: content, structured_content: structured_content}} ->
        if function_exported?(opts.host, :handle_update_model_context, 3) do
          case opts.host.handle_update_model_context(host_conn, content, structured_content) do
            :ok ->
              send_result(conn, %{}, id)

            {:error, reason} ->
              send_error(conn, -32603, "Update model context failed", reason, id)
          end
        else
          send_error(
            conn,
            -32601,
            "Method not supported",
            "Host does not support model context updates",
            id
          )
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ui/notifications/size-changed ─────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/notifications/size-changed", params: params},
         opts,
         host_conn
       ) do
    case Messages.decode_size_changed(params || %{}) do
      {:ok, %{width: width, height: height}} ->
        if function_exported?(opts.host, :handle_size_changed, 3) do
          opts.host.handle_size_changed(host_conn, width, height)
        end

        # Notifications get 202 with no body
        conn |> send_resp(202, "") |> halt()

      {:error, _reason} ->
        # Notifications don't return errors, just acknowledge
        conn |> send_resp(202, "") |> halt()
    end
  end

  # ── ui/resource-teardown (from view acknowledging teardown) ───────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "ui/resource-teardown", params: params, id: id},
         opts,
         host_conn
       ) do
    case Messages.decode_resource_teardown(params || %{}) do
      {:ok, _reason} ->
        if function_exported?(opts.host, :handle_teardown_response, 1) do
          opts.host.handle_teardown_response(host_conn)
        end

        if id do
          send_result(conn, %{}, id)
        else
          conn |> send_resp(202, "") |> halt()
        end

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── tools/call (proxied to router) ────────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "tools/call", params: params, id: id},
         opts,
         _host_conn
       ) do
    tool_name = Map.get(params || %{}, "name")
    arguments = Map.get(params || %{}, "arguments", %{})
    mcp_conn = %McpServer.Conn{}

    case opts.router.call_tool(mcp_conn, tool_name, arguments) do
      {:ok, %McpServer.Tool.CallResult{} = call_result} ->
        send_result(conn, call_result, id)

      {:ok, content} ->
        result = %{"content" => content, "isError" => false}
        send_result(conn, result, id)

      {:error, error_message} ->
        result = %{
          "content" => [%{"type" => "text", "text" => "Error: #{error_message}"}],
          "isError" => true
        }

        send_result(conn, result, id)
    end
  end

  # ── resources/read (proxied to router) ────────────────────────────

  defp handle_request(
         conn,
         %JsonRpc.Request{method: "resources/read", params: params, id: id},
         opts,
         _host_conn
       ) do
    uri = Map.get(params || %{}, "uri")
    mcp_conn = %McpServer.Conn{}

    case find_and_read_resource(opts.router, mcp_conn, uri) do
      {:ok, result} ->
        send_result(conn, result, id)

      {:error, reason} ->
        send_error(conn, -32602, "Invalid params", reason, id)
    end
  end

  # ── ping ──────────────────────────────────────────────────────────

  defp handle_request(conn, %JsonRpc.Request{method: "ping", id: id}, _opts, _host_conn) do
    send_result(conn, %{}, id)
  end

  # ── Unknown method ────────────────────────────────────────────────

  defp handle_request(conn, %JsonRpc.Request{method: method, id: id}, _opts, _host_conn) do
    send_error(conn, -32601, "Method not found", %{"method" => method}, id)
  end

  # ── Notification Helpers (for host → view) ────────────────────────

  @doc "Builds a `ui/notifications/tool-input` notification map."
  @spec notify_tool_input(map()) :: map()
  def notify_tool_input(arguments) do
    Messages.encode_tool_input(arguments)
  end

  @doc "Builds a `ui/notifications/tool-input-partial` notification map."
  @spec notify_tool_input_partial(map()) :: map()
  def notify_tool_input_partial(arguments) do
    Messages.encode_tool_input_partial(arguments)
  end

  @doc "Builds a `ui/notifications/tool-result` notification map."
  @spec notify_tool_result(map()) :: map()
  def notify_tool_result(call_tool_result) do
    Messages.encode_tool_result(call_tool_result)
  end

  @doc "Builds a `ui/notifications/tool-cancelled` notification map."
  @spec notify_tool_cancelled(String.t()) :: map()
  def notify_tool_cancelled(reason) do
    Messages.encode_tool_cancelled(reason)
  end

  @doc "Builds a `ui/notifications/host-context-changed` notification map."
  @spec notify_host_context_changed(map()) :: map()
  def notify_host_context_changed(partial_context) do
    Messages.encode_host_context_changed(partial_context)
  end

  @doc "Builds a `ui/resource-teardown` request."
  @spec notify_resource_teardown(String.t(), String.t() | integer()) :: JsonRpc.Request.t()
  def notify_resource_teardown(reason, id) do
    Messages.encode_resource_teardown(reason, id)
  end

  # ── Private Helpers ───────────────────────────────────────────────

  defp send_result(conn, result, id) do
    response =
      JsonRpc.new_response(result, id)
      |> JsonRpc.encode_response()
      |> Jason.encode!()

    conn |> send_resp(200, response) |> halt()
  end

  defp send_error(conn, code, message, data, id) do
    data = if is_binary(data), do: %{"message" => data}, else: data

    error_response =
      JsonRpc.new_error_response(code, message, data, id)
      |> JsonRpc.encode_response()
      |> Jason.encode!()

    status = if code == -32602, do: 400, else: 500

    conn |> send_resp(status, error_response) |> halt()
  end

  defp find_and_read_resource(router, mcp_conn, uri) when is_binary(uri) do
    # Check static resources first
    case router.list_resources(mcp_conn) do
      {:ok, static_resources} ->
        case Enum.find(static_resources, fn res -> res.uri == uri end) do
          %{name: name} ->
            router.read_resource(mcp_conn, name, %{})

          nil ->
            # Check template resources
            case router.list_templates_resource(mcp_conn) do
              {:ok, templates} ->
                templates
                |> Enum.find_value({:error, "Resource not found"}, fn res ->
                  if is_binary(res.uri_template) do
                    tpl = McpServer.URITemplate.new(res.uri_template)

                    case McpServer.URITemplate.match(tpl, uri) do
                      {:ok, vars_map} when is_map(vars_map) ->
                        router.read_resource(mcp_conn, res.name, vars_map)

                      _ ->
                        false
                    end
                  else
                    false
                  end
                end)

              {:error, _} ->
                {:error, "Resource not found"}
            end
        end

      {:error, _} ->
        {:error, "Resource not found"}
    end
  end

  defp find_and_read_resource(_router, _mcp_conn, _uri), do: {:error, "Invalid URI"}
end
