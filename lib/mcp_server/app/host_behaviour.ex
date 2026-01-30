defmodule McpServer.App.Host do
  @moduledoc """
  Behaviour for implementing an MCP Apps host.

  A host manages the lifecycle of UI views (iframes), proxies tool calls
  to MCP servers, and handles view requests like opening links or
  sending messages to the chat interface.

  ## Usage

  Implement this behaviour in a module that will handle view requests:

      defmodule MyApp.HostHandler do
        @behaviour McpServer.App.Host

        @impl true
        def handle_initialize(_host_conn, _app_capabilities) do
          host_caps = McpServer.App.HostCapabilities.new(
            open_links: %{},
            server_tools: %{list_changed: false},
            logging: %{}
          )

          host_ctx = McpServer.App.HostContext.new(
            theme: "dark",
            display_mode: "inline",
            available_display_modes: ["inline", "fullscreen"],
            locale: "en-US"
          )

          {:ok, %{host_capabilities: host_caps, host_context: host_ctx}}
        end

        @impl true
        def handle_open_link(_host_conn, url) do
          # Open URL in the user's browser
          System.cmd("open", [url])
          :ok
        end

        @impl true
        def handle_message(_host_conn, role, content) do
          # Add message to conversation
          IO.inspect({role, content}, label: "View message")
          :ok
        end
      end

  Then mount `McpServer.App.HostPlug` with your handler:

      plug McpServer.App.HostPlug,
        host: MyApp.HostHandler,
        router: MyApp.Router

  ## Callbacks

  All callbacks receive a host connection context as the first argument.
  The context is an opaque map that can carry session-specific data.
  """

  @type host_conn :: map()

  @doc """
  Handle view initialization.

  Called when a view sends `ui/initialize`. Must return host capabilities
  and context for the view.
  """
  @callback handle_initialize(host_conn(), McpServer.App.AppCapabilities.t()) ::
              {:ok,
               %{
                 host_capabilities: McpServer.App.HostCapabilities.t(),
                 host_context: McpServer.App.HostContext.t()
               }}
              | {:error, String.t()}

  @doc """
  Handle a request to open an external link.

  Called when a view sends `ui/open-link`. The host should open the URL
  in the user's browser or appropriate application.
  """
  @callback handle_open_link(host_conn(), url :: String.t()) ::
              :ok | {:error, String.t()}

  @doc """
  Handle a message from the view to the chat interface.

  Called when a view sends `ui/message`. The host should add the message
  to the conversation context.
  """
  @callback handle_message(host_conn(), role :: String.t(), content :: map()) ::
              :ok | {:error, String.t()}

  @doc """
  Handle a display mode change request.

  Called when a view sends `ui/request-display-mode`. Returns the actual
  mode that was set (which may differ from the requested mode).
  """
  @callback handle_request_display_mode(host_conn(), mode :: String.t()) ::
              {:ok, actual_mode :: String.t()} | {:error, String.t()}

  @doc """
  Handle a model context update from the view.

  Called when a view sends `ui/update-model-context`. The host should
  provide the updated context to the model in future turns.
  """
  @callback handle_update_model_context(
              host_conn(),
              content :: list() | nil,
              structured_content :: map() | nil
            ) ::
              :ok | {:error, String.t()}

  @doc """
  Handle a size change notification from the view.

  Called when a view sends `ui/notifications/size-changed`. The host
  should update the iframe dimensions accordingly.
  """
  @callback handle_size_changed(host_conn(), width :: number(), height :: number()) ::
              :ok

  @doc """
  Handle a teardown acknowledgment from the view.

  Called when a view responds to `ui/resource-teardown`. The host can
  proceed with destroying the view.
  """
  @callback handle_teardown_response(host_conn()) ::
              :ok

  @optional_callbacks handle_open_link: 2,
                      handle_message: 3,
                      handle_request_display_mode: 2,
                      handle_update_model_context: 3,
                      handle_size_changed: 3,
                      handle_teardown_response: 1
end
