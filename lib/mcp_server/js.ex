defmodule McpServer.JS do
  @moduledoc """
  Provides inline JavaScript helpers for MCP Apps.

  Use `mcp_app_script/0` to embed the `McpApp` client class directly
  into an HTML template (e.g., EEx) so the iframe app has no external
  script dependencies.

  ## Example

      # In a .html.eex template:
      <script><%= McpServer.JS.mcp_app_script() %></script>
  """

  @doc """
  Returns the contents of `priv/js/mcp_app.js` as a string.

  Intended to be embedded inside a `<script>` tag in your MCP App HTML.
  """
  @spec mcp_app_script() :: String.t()
  def mcp_app_script do
    :mcp_server
    |> :code.priv_dir()
    |> Path.join("js/mcp_app.js")
    |> File.read!()
  end
end
