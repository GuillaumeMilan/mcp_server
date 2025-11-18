defmodule McpServer.Telemetry do
  @moduledoc """
  Telemetry events for MCP Server.

  This module provides telemetry instrumentation for monitoring and observability
  of your MCP server. All events follow the pattern `[:mcp_server, :category, :event]`.

  ## Available Events

  ### HTTP Request Lifecycle

  * `[:mcp_server, :request, :start]` - Emitted when an HTTP request is received
  * `[:mcp_server, :request, :stop]` - Emitted when an HTTP request completes successfully
  * `[:mcp_server, :request, :exception]` - Emitted when an HTTP request fails with an exception

  ### Tool Operations

  * `[:mcp_server, :tool, :call_start]` - Emitted when a tool execution starts
  * `[:mcp_server, :tool, :call_stop]` - Emitted when a tool execution completes
  * `[:mcp_server, :tool, :call_exception]` - Emitted when a tool execution fails
  * `[:mcp_server, :tool, :list]` - Emitted when tools are listed

  ### Prompt Operations

  * `[:mcp_server, :prompt, :get_start]` - Emitted when a prompt retrieval starts
  * `[:mcp_server, :prompt, :get_stop]` - Emitted when a prompt retrieval completes
  * `[:mcp_server, :prompt, :get_exception]` - Emitted when a prompt retrieval fails
  * `[:mcp_server, :prompt, :list]` - Emitted when prompts are listed

  ### Resource Operations

  * `[:mcp_server, :resource, :read_start]` - Emitted when a resource read starts
  * `[:mcp_server, :resource, :read_stop]` - Emitted when a resource read completes
  * `[:mcp_server, :resource, :read_exception]` - Emitted when a resource read fails
  * `[:mcp_server, :resource, :list]` - Emitted when static resources are listed
  * `[:mcp_server, :resource, :templates_list]` - Emitted when resource templates are listed

  ### Completion Operations

  * `[:mcp_server, :completion, :start]` - Emitted when a completion request starts
  * `[:mcp_server, :completion, :stop]` - Emitted when a completion request completes
  * `[:mcp_server, :completion, :exception]` - Emitted when a completion request fails

  ### Session Lifecycle

  * `[:mcp_server, :session, :init]` - Emitted when a new session is initialized
  * `[:mcp_server, :session, :initialized]` - Emitted when a client sends initialized notification

  ### Logging Configuration

  * `[:mcp_server, :logging, :set_level]` - Emitted when log level is changed

  ### Validation & Errors

  * `[:mcp_server, :validation, :error]` - Emitted when argument validation fails
  * `[:mcp_server, :json_rpc, :decode_error]` - Emitted when JSON-RPC parsing fails

  ## Usage Example

  ```elixir
  # Attach to telemetry events in your application
  :telemetry.attach_many(
    "mcp-server-metrics",
    [
      [:mcp_server, :tool, :call_stop],
      [:mcp_server, :request, :stop]
    ],
    &MyApp.Metrics.handle_event/4,
    nil
  )

  # Handler function
  defmodule MyApp.Metrics do
    def handle_event([:mcp_server, :tool, :call_stop], measurements, metadata, _config) do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      MyApp.StatsD.timing("mcp.tool.duration", duration_ms, tags: [tool: metadata.tool_name])
    end

    def handle_event([:mcp_server, :request, :stop], measurements, metadata, _config) do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      MyApp.StatsD.timing("mcp.request.duration", duration_ms, tags: [method: metadata.method])
    end
  end
  ```

  ## Measurements

  Most `:stop` and `:exception` events include:
  * `:duration` - Time elapsed in native time units (use `System.convert_time_unit/3` to convert)

  List events include:
  * `:count` - Number of items returned

  ## Metadata

  All events include relevant context such as:
  * `:session_id` - The session identifier
  * `:method` - The JSON-RPC method (for request events)
  * `:tool_name` / `:prompt_name` / `:resource_name` - The name of the item being operated on
  * `:error` - Error details (for exception events)
  """

  @doc """
  Executes a function and emits telemetry events for start, stop, and exception.

  This is the recommended way to instrument operations that can fail.

  ## Example

      Telemetry.span(
        [:mcp_server, :tool, :call],
        %{session_id: session_id, tool_name: tool_name},
        fn ->
          result = router.call_tool(mcp_conn, tool_name, arguments)
          {result, %{result_count: count_results(result)}}
        end
      )
  """
  @spec span(
          event_prefix :: [atom()],
          start_metadata :: map(),
          span_function :: (-> {result, stop_metadata :: map()})
        ) :: result
        when result: any()
  def span(event_prefix, start_metadata, span_function) when is_function(span_function, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      start_metadata
    )

    try do
      {result, extra_metadata} = span_function.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(start_metadata, extra_metadata)
      )

      result
    rescue
      exception ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(start_metadata, %{
            kind: :error,
            error: exception,
            stacktrace: __STACKTRACE__
          })
        )

        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(start_metadata, %{
            kind: kind,
            error: reason,
            stacktrace: __STACKTRACE__
          })
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Emits a single telemetry event.

  ## Example

      Telemetry.execute(
        [:mcp_server, :session, :init],
        %{system_time: System.system_time()},
        %{session_id: session_id, client_info: client_info}
      )
  """
  @spec execute(event :: [atom()], measurements :: map(), metadata :: map()) :: :ok
  def execute(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  # Event name helpers for consistency

  @doc false
  def event_request_start, do: [:mcp_server, :request, :start]
  @doc false
  def event_request_stop, do: [:mcp_server, :request, :stop]
  @doc false
  def event_request_exception, do: [:mcp_server, :request, :exception]

  @doc false
  def event_tool_call, do: [:mcp_server, :tool, :call]
  @doc false
  def event_tool_list, do: [:mcp_server, :tool, :list]

  @doc false
  def event_prompt_get, do: [:mcp_server, :prompt, :get]
  @doc false
  def event_prompt_list, do: [:mcp_server, :prompt, :list]

  @doc false
  def event_resource_read, do: [:mcp_server, :resource, :read]
  @doc false
  def event_resource_list, do: [:mcp_server, :resource, :list]
  @doc false
  def event_resource_templates_list, do: [:mcp_server, :resource, :templates_list]

  @doc false
  def event_completion, do: [:mcp_server, :completion]

  @doc false
  def event_session_init, do: [:mcp_server, :session, :init]
  @doc false
  def event_session_initialized, do: [:mcp_server, :session, :initialized]

  @doc false
  def event_logging_set_level, do: [:mcp_server, :logging, :set_level]

  @doc false
  def event_validation_error, do: [:mcp_server, :validation, :error]
  @doc false
  def event_json_rpc_decode_error, do: [:mcp_server, :json_rpc, :decode_error]
end
