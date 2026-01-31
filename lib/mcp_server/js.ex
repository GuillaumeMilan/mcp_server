defmodule McpServer.JS do
  @moduledoc """
  Provides inline JavaScript helpers for MCP Apps.

  Use `mcp_app_script/1` to embed the `McpApp` client class directly
  into an HTML template (e.g., EEx) so the iframe app has no external
  script dependencies. Server info from the MCP connection is baked
  into the script as default `appInfo` and `protocolVersion`.

  ## Example

      # In a .html.eex template:
      <script><%= McpServer.JS.mcp_app_script(conn) %></script>
  """

  @template_path Path.join(:code.priv_dir(:mcp_server), "js/mcp_app.js.eex")

  @doc """
  Renders `priv/js/mcp_app.js.eex` with server info from the MCP connection.

  The `server_info` stored in `conn.private[:server_info]` (a map with
  `:name` and `:version` keys) is used as the default `appInfo` in the
  generated `McpApp` class.

  ## Parameters

  - `conn` — A `McpServer.Conn` struct (the one your controllers receive).
  """
  @spec mcp_app_script(McpServer.Conn.t()) :: String.t()
  def mcp_app_script(%McpServer.Conn{} = conn) do
    server_info = McpServer.Conn.get_private(conn, :server_info, %{})

    app_info = %{
      "name" => Map.get(server_info, :name, Map.get(server_info, "name", "mcp-app")),
      "version" => Map.get(server_info, :version, Map.get(server_info, "version", "1.0.0"))
    }

    EEx.eval_file(@template_path,
      assigns: [
        protocol_version: "0.3",
        app_info_json: Jason.encode!(app_info)
      ]
    )
  end
end
