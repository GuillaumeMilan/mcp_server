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

  defp setup_connection(conn, opts) do
    conn
    |> put_private(:router, opts.router)
    |> put_private(:server_info, opts.server_info)
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

      Logger.debug("""
      Received:
      #{inspect(request)}
      """)

      handle_request(conn, request)
    else
      {:error, reason} ->
        Logger.error("""
        Failed to decode request: #{inspect(reason)}
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
    result = %{
      "capabilities" => %{
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

    Logger.info("Sending initialize response: #{inspect(response)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "notifications/initialized"}) do
    # This is a notification (no id), so we don't send a response
    Logger.info("Client has been initialized")

    # Just return 200 OK for notifications
    send_resp(conn, 200, "")
  end

  def handle_request(conn, %JsonRpc.Request{method: "tools/list", id: id}) do
    router = conn.private.router

    result = %{
      "tools" => router.tools_list()
    }

    response = JsonRpc.new_response(result, id)
    response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

    Logger.info("Sending tools/list response: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: "tools/call", params: params, id: id}) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})
    router = conn.private.router

    Logger.info(
      "Tool call request - Name: #{inspect(tool_name)}, Arguments: #{inspect(arguments)}"
    )

    router.tools_call(tool_name, arguments)
    |> case do
      {:ok, content} ->
        result = %{
          "content" => content,
          "isError" => false
        }

        response = JsonRpc.new_response(result, id)
        response_json = response |> JsonRpc.encode_response() |> Jason.encode!()

        Logger.info("Tool call successful: #{inspect(result)}")
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

        Logger.error("Tool call failed: #{error_message}")
        send_resp(conn, 200, response_json)

      _ ->
        Logger.error("Unexpected response format from tool call")

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

    Logger.info("Sending prompts/list response: #{inspect(result)}")

    send_resp(conn, 200, response_json)
  end

  def handle_request(conn, %JsonRpc.Request{method: method}) do
    Logger.warning("Unhandled method: #{inspect(method)}")

    error_response =
      JsonRpc.new_error_response(-32601, "Method not found", %{"method" => method}, nil)
      |> JsonRpc.encode_response()
      |> Jason.encode!()

    send_resp(conn, 501, error_response)
  end
end
