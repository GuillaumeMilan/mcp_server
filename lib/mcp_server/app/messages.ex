defmodule McpServer.App.Messages do
  @moduledoc """
  JSON-RPC message helpers for MCP Apps `ui/*` protocol methods.

  Provides encode and decode functions for all messages exchanged between
  hosts and views in the MCP Apps protocol. These helpers produce
  `McpServer.JsonRpc.Request` structs or notification maps that can be
  serialized to JSON.

  ## Message Categories

  ### View-to-Host Requests (host receives)
  - `ui/open-link` — View requests host to open an external URL
  - `ui/message` — View sends a message to the host's chat
  - `ui/request-display-mode` — View requests a display mode change
  - `ui/update-model-context` — View updates the model context

  ### Host-to-View Notifications (host sends)
  - `ui/notifications/tool-input` — Complete tool arguments
  - `ui/notifications/tool-input-partial` — Streaming partial tool arguments
  - `ui/notifications/tool-result` — Tool execution result
  - `ui/notifications/tool-cancelled` — Tool execution was cancelled
  - `ui/notifications/host-context-changed` — Host context changed
  - `ui/notifications/size-changed` — View size changed

  ### Bidirectional
  - `ui/resource-teardown` — Before teardown notification
  - `ui/initialize` — View initialization handshake
  """

  alias McpServer.JsonRpc

  # ── View Initialization ──────────────────────────────────────────

  @doc "Encodes a `ui/initialize` request from a view."
  @spec encode_initialize_request(McpServer.App.AppCapabilities.t(), String.t() | integer()) ::
          JsonRpc.Request.t()
  def encode_initialize_request(app_capabilities, id) do
    JsonRpc.new_request("ui/initialize", %{"appCapabilities" => app_capabilities}, id)
  end

  @doc "Encodes a `ui/initialize` response from a host."
  @spec encode_initialize_response(
          McpServer.App.HostCapabilities.t(),
          McpServer.App.HostContext.t(),
          String.t() | integer()
        ) :: JsonRpc.Response.t()
  def encode_initialize_response(host_capabilities, host_context, id) do
    result = %{
      "hostCapabilities" => host_capabilities,
      "hostContext" => host_context
    }

    JsonRpc.new_response(result, id)
  end

  @doc "Decodes `ui/initialize` request params into an AppCapabilities struct."
  @spec decode_initialize_request(map()) ::
          {:ok, McpServer.App.AppCapabilities.t()} | {:error, String.t()}
  def decode_initialize_request(params) when is_map(params) do
    app_caps = Map.get(params, "appCapabilities", %{})

    {:ok,
     McpServer.App.AppCapabilities.new(
       experimental: Map.get(app_caps, "experimental"),
       tools: decode_tools_capability(Map.get(app_caps, "tools")),
       available_display_modes: Map.get(app_caps, "availableDisplayModes")
     )}
  end

  def decode_initialize_request(_), do: {:error, "Invalid ui/initialize params"}

  # ── View-to-Host Requests ────────────────────────────────────────

  @doc "Encodes a `ui/open-link` request."
  @spec encode_open_link(String.t(), String.t() | integer()) :: JsonRpc.Request.t()
  def encode_open_link(url, id) do
    JsonRpc.new_request("ui/open-link", %{"url" => url}, id)
  end

  @doc "Decodes `ui/open-link` params."
  @spec decode_open_link(map()) :: {:ok, String.t()} | {:error, String.t()}
  def decode_open_link(%{"url" => url}) when is_binary(url), do: {:ok, url}
  def decode_open_link(_), do: {:error, "Invalid ui/open-link params: missing url"}

  @doc "Encodes a `ui/message` request."
  @spec encode_message(String.t(), map(), String.t() | integer()) :: JsonRpc.Request.t()
  def encode_message(role, content, id) do
    JsonRpc.new_request("ui/message", %{"role" => role, "content" => content}, id)
  end

  @doc "Decodes `ui/message` params."
  @spec decode_message(map()) :: {:ok, %{role: String.t(), content: map()}} | {:error, String.t()}
  def decode_message(%{"role" => role, "content" => content})
      when is_binary(role) and is_map(content) do
    {:ok, %{role: role, content: content}}
  end

  def decode_message(_), do: {:error, "Invalid ui/message params"}

  @doc "Encodes a `ui/request-display-mode` request."
  @spec encode_request_display_mode(String.t(), String.t() | integer()) :: JsonRpc.Request.t()
  def encode_request_display_mode(mode, id) do
    JsonRpc.new_request("ui/request-display-mode", %{"mode" => mode}, id)
  end

  @doc "Decodes `ui/request-display-mode` params."
  @spec decode_request_display_mode(map()) :: {:ok, String.t()} | {:error, String.t()}
  def decode_request_display_mode(%{"mode" => mode}) when is_binary(mode), do: {:ok, mode}
  def decode_request_display_mode(_), do: {:error, "Invalid ui/request-display-mode params"}

  @doc "Encodes a `ui/update-model-context` request."
  @spec encode_update_model_context(list() | nil, map() | nil, String.t() | integer()) ::
          JsonRpc.Request.t()
  def encode_update_model_context(content, structured_content, id) do
    params = %{}
    params = if content, do: Map.put(params, "content", content), else: params

    params =
      if structured_content,
        do: Map.put(params, "structuredContent", structured_content),
        else: params

    JsonRpc.new_request("ui/update-model-context", params, id)
  end

  @doc "Decodes `ui/update-model-context` params."
  @spec decode_update_model_context(map()) ::
          {:ok, %{content: list() | nil, structured_content: map() | nil}}
  def decode_update_model_context(params) when is_map(params) do
    {:ok,
     %{
       content: Map.get(params, "content"),
       structured_content: Map.get(params, "structuredContent")
     }}
  end

  # ── Host-to-View Notifications ───────────────────────────────────

  @doc "Encodes a `ui/notifications/tool-input` notification."
  @spec encode_tool_input(map()) :: map()
  def encode_tool_input(arguments) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/tool-input",
      "params" => %{"arguments" => arguments}
    }
  end

  @doc "Decodes `ui/notifications/tool-input` params."
  @spec decode_tool_input(map()) :: {:ok, map()} | {:error, String.t()}
  def decode_tool_input(%{"arguments" => arguments}) when is_map(arguments),
    do: {:ok, arguments}

  def decode_tool_input(_), do: {:error, "Invalid ui/notifications/tool-input params"}

  @doc "Encodes a `ui/notifications/tool-input-partial` notification."
  @spec encode_tool_input_partial(map()) :: map()
  def encode_tool_input_partial(arguments) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/tool-input-partial",
      "params" => %{"arguments" => arguments}
    }
  end

  @doc "Decodes `ui/notifications/tool-input-partial` params."
  @spec decode_tool_input_partial(map()) :: {:ok, map()} | {:error, String.t()}
  def decode_tool_input_partial(%{"arguments" => arguments}) when is_map(arguments),
    do: {:ok, arguments}

  def decode_tool_input_partial(_),
    do: {:error, "Invalid ui/notifications/tool-input-partial params"}

  @doc "Encodes a `ui/notifications/tool-result` notification."
  @spec encode_tool_result(map()) :: map()
  def encode_tool_result(call_tool_result) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/tool-result",
      "params" => call_tool_result
    }
  end

  @doc "Encodes a `ui/notifications/tool-cancelled` notification."
  @spec encode_tool_cancelled(String.t()) :: map()
  def encode_tool_cancelled(reason) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/tool-cancelled",
      "params" => %{"reason" => reason}
    }
  end

  @doc "Decodes `ui/notifications/tool-cancelled` params."
  @spec decode_tool_cancelled(map()) :: {:ok, String.t()} | {:error, String.t()}
  def decode_tool_cancelled(%{"reason" => reason}) when is_binary(reason), do: {:ok, reason}
  def decode_tool_cancelled(_), do: {:error, "Invalid ui/notifications/tool-cancelled params"}

  @doc "Encodes a `ui/notifications/host-context-changed` notification."
  @spec encode_host_context_changed(map()) :: map()
  def encode_host_context_changed(partial_context) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/host-context-changed",
      "params" => partial_context
    }
  end

  @doc "Encodes a `ui/notifications/size-changed` notification."
  @spec encode_size_changed(number(), number()) :: map()
  def encode_size_changed(width, height) do
    %{
      "jsonrpc" => "2.0",
      "method" => "ui/notifications/size-changed",
      "params" => %{"width" => width, "height" => height}
    }
  end

  @doc "Decodes `ui/notifications/size-changed` params."
  @spec decode_size_changed(map()) ::
          {:ok, %{width: number(), height: number()}} | {:error, String.t()}
  def decode_size_changed(%{"width" => width, "height" => height})
      when is_number(width) and is_number(height) do
    {:ok, %{width: width, height: height}}
  end

  def decode_size_changed(_), do: {:error, "Invalid ui/notifications/size-changed params"}

  # ── Bidirectional ────────────────────────────────────────────────

  @doc "Encodes a `ui/resource-teardown` request."
  @spec encode_resource_teardown(String.t(), String.t() | integer()) :: JsonRpc.Request.t()
  def encode_resource_teardown(reason, id) do
    JsonRpc.new_request("ui/resource-teardown", %{"reason" => reason}, id)
  end

  @doc "Decodes `ui/resource-teardown` params."
  @spec decode_resource_teardown(map()) :: {:ok, String.t()} | {:error, String.t()}
  def decode_resource_teardown(%{"reason" => reason}) when is_binary(reason), do: {:ok, reason}
  def decode_resource_teardown(_), do: {:error, "Invalid ui/resource-teardown params"}

  # ── Helpers ──────────────────────────────────────────────────────

  defp decode_tools_capability(nil), do: nil

  defp decode_tools_capability(tools) when is_map(tools) do
    %{list_changed: Map.get(tools, "listChanged", false)}
  end
end
